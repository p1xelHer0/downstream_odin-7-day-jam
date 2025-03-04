package tracking_allocator

import "core:fmt"
import "core:mem"

tracking_allocator_reset :: proc(alloc: ^mem.Tracking_Allocator) -> bool
{
  err := tracking_allocator_check(alloc)

  mem.tracking_allocator_clear(alloc)

  return err
}

tracking_allocator_end :: proc(alloc: ^mem.Tracking_Allocator) -> bool
{
  err := tracking_allocator_check(alloc)

  mem.tracking_allocator_destroy(alloc)

  return err
}

tracking_allocator_check :: proc(alloc: ^mem.Tracking_Allocator) -> bool
{
  err := false

  if len(alloc.allocation_map) > 0
  {
    err = true

    fmt.eprintf("=== %v allocations not freed: ===\n", len(alloc.allocation_map))
    for _, entry in alloc.allocation_map
    {
      fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
    }
  }

  if len(alloc.bad_free_array) > 0
  {
    err = true

    fmt.eprintf("=== %v incorrect frees: ===\n", len(alloc.bad_free_array))
    for entry in alloc.bad_free_array
    {
      fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
    }
  }

  return err
}
