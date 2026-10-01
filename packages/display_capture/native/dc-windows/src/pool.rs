//! Latest-wins slot bookkeeping for the shared texture pool (SPEC Â§6.4, Â§7.2).
//!
//! Pure logic, no GPU types, so it can be unit tested.
//!
//! * The producer asks for a slot to write ([`SlotPool::begin_write`]), writes,
//!   then publishes it ([`SlotPool::publish`]) which makes it the *current* frame.
//! * The consumer (Flutter's raster thread) acquires the current frame
//!   ([`SlotPool::acquire`]); the slot stays pinned until [`SlotPool::release`].
//! * A pinned slot is never handed to the producer, so with 3 slots the
//!   producer always has one to write (consumer holds at most one).

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
struct SlotState {
    pins: u32,
    writing: bool,
}

#[derive(Debug)]
pub struct SlotPool {
    slots: Vec<SlotState>,
    current: Option<usize>,
}

impl SlotPool {
    pub fn new(len: usize) -> Self {
        Self { slots: vec![SlotState::default(); len], current: None }
    }

    #[cfg(test)]
    pub fn len(&self) -> usize {
        self.slots.len()
    }

    #[cfg(test)]
    pub fn current(&self) -> Option<usize> {
        self.current
    }

    /// Picks a slot to write: prefer one that is neither pinned nor current;
    /// otherwise overwrite the (unpinned) current one. `None` if all pinned.
    pub fn begin_write(&mut self) -> Option<usize> {
        let free = (0..self.slots.len()).find(|&i| {
            let s = self.slots[i];
            s.pins == 0 && !s.writing && Some(i) != self.current
        });
        let pick = free.or_else(|| {
            (0..self.slots.len()).find(|&i| {
                let s = self.slots[i];
                s.pins == 0 && !s.writing
            })
        })?;
        self.slots[pick].writing = true;
        Some(pick)
    }

    /// The slot finished writing and becomes the current frame.
    pub fn publish(&mut self, slot: usize) {
        self.slots[slot].writing = false;
        self.current = Some(slot);
    }

    /// The write failed/was dropped: the slot is free again, current unchanged.
    pub fn abort_write(&mut self, slot: usize) {
        self.slots[slot].writing = false;
    }

    /// Pins and returns the current frame, if any.
    pub fn acquire(&mut self) -> Option<usize> {
        let i = self.current?;
        self.slots[i].pins += 1;
        Some(i)
    }

    pub fn release(&mut self, slot: usize) {
        if let Some(s) = self.slots.get_mut(slot) {
            s.pins = s.pins.saturating_sub(1);
        }
    }

    /// Drops every frame (used when the pool is rebuilt after a size change).
    pub fn reset(&mut self, len: usize) {
        self.slots = vec![SlotState::default(); len];
        self.current = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn publish_makes_frame_current() {
        let mut p = SlotPool::new(3);
        assert_eq!(p.acquire(), None);
        let s = p.begin_write().unwrap();
        p.publish(s);
        assert_eq!(p.current(), Some(s));
    }

    #[test]
    fn acquire_pins_and_writer_skips_pinned() {
        let mut p = SlotPool::new(3);
        let a = p.begin_write().unwrap();
        p.publish(a);
        let got = p.acquire().unwrap();
        assert_eq!(got, a);
        // writes never land on the pinned slot, even over many frames
        for _ in 0..10 {
            let w = p.begin_write().unwrap();
            assert_ne!(w, a);
            p.publish(w);
        }
        // pinned slot is current-no-more but still pinned; release frees it
        p.release(a);
        let mut seen_a = false;
        for _ in 0..4 {
            let w = p.begin_write().unwrap();
            seen_a |= w == a;
            p.publish(w);
        }
        assert!(seen_a);
    }

    #[test]
    fn reuses_unpinned_current_when_no_other_free() {
        let mut p = SlotPool::new(2);
        let a = p.begin_write().unwrap();
        p.publish(a);
        let b = p.begin_write().unwrap();
        p.publish(b);
        let _pin = p.acquire().unwrap(); // pins b (current)
        let w = p.begin_write().unwrap();
        assert_eq!(w, a); // the only unpinned one
        p.publish(w);
    }

    #[test]
    fn all_pinned_means_drop() {
        let mut p = SlotPool::new(1);
        let a = p.begin_write().unwrap();
        p.publish(a);
        p.acquire().unwrap();
        assert_eq!(p.begin_write(), None);
    }

    #[test]
    fn abort_write_keeps_previous_current() {
        let mut p = SlotPool::new(3);
        let a = p.begin_write().unwrap();
        p.publish(a);
        let b = p.begin_write().unwrap();
        p.abort_write(b);
        assert_eq!(p.current(), Some(a));
        assert_eq!(p.begin_write(), Some(b)); // free again
    }

    #[test]
    fn same_frame_can_be_acquired_repeatedly() {
        let mut p = SlotPool::new(3);
        let a = p.begin_write().unwrap();
        p.publish(a);
        assert_eq!(p.acquire(), Some(a));
        assert_eq!(p.acquire(), Some(a));
        p.release(a);
        p.release(a);
        p.release(a); // extra release must not underflow
        assert!(p.begin_write().is_some());
    }

    #[test]
    fn reset_clears_current() {
        let mut p = SlotPool::new(3);
        let a = p.begin_write().unwrap();
        p.publish(a);
        p.reset(3);
        assert_eq!(p.current(), None);
    }
}

