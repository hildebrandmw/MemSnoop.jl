# Routines implementing Idle Page Tracking
include("vma.jl")
include("sample.jl")

## Idle Page Tracking
"""
Measurement type for performing Idle Page Tracking on a process. To filter process VMAs,
construct as
```julia
    IdlePageTracker(filter)
```
where `filter` is a [`VMA`](@ref) filter function.

Implementation Details
----------------------
* `filter` - The VMA filter to apply.
* `vmas::Vector{VMA}` - Buffer for storing VMAs.
* `buffer::Vector{UInt64}` - Buffer to store the idle page bitmap.
"""
struct IdlePageTracker{T <: Function} <: AbstractMeasurement 
    filter::T
    vmas::Vector{VMA}
    buffer::Vector{UInt64}
end
IdlePageTracker(f::Function = tautology) = IdlePageTracker(f, VMA[], UInt64[])


initialize!(I::IdlePageTracker, process) = initbuffer!(I)

prepare(::IdlePageTracker) = Sample[]
function measure(I::IdlePageTracker, process)
    # Get VMAs, read idle bits and set idle bits
    getvmas!(I.vmas, getpid(process), I.filter)
    pages = readidle(getpid(process), I.vmas, I.buffer)
    markidle(getpid(process), I.vmas)

    return Sample(copy(I.vmas), pages)
end

#####
##### Implementations
#####

"""
    initbuffer!(I::IdlePageTracker)

Read once from `page_idle/bitmap` to get the size of the bitmap. Set the `bitmap` in
`I` to this size to avoid reallocation every time the bitmap is read.
"""
function initbuffer!(I::IdlePageTracker)
    # Get the number of bytes in the bitmap
    # Since this isn't a normal file, normal methods like "filesize" or "seekend" don't
    # work, so we actually have to buffer the whole array once to get the size. Since this
    # only happens at the beginning of a trace, it's okay to pay this additional latency.
    nentries = open(IDLE_BITMAP) do bitmap
        buffer = reinterpret(UInt64, read(bitmap))
        return length(buffer)
    end
    resize!(I.buffer, nentries)
    return nothing
end



#####
##### Page Walking Functions
#####

"""
    walkpagemap(f::Function, pid, vmas; [buffer::Vector{UInt64}])

For each [`VMA`](@ref) in iterator `vmas`, store the contents of `/proc/pid/pagemap` into
`buffer` for this `VMA` and call `f(buffer)`.

Note that it is possible for `buffer` to be empty.
"""
function walkpagemap(f::Function, pid, vmas; buffer::Vector{UInt64} = UInt64[])
    # Open the pagemap file. Expect address ranges for the VMAs to be in order.
    try
        open("/proc/$pid/pagemap") do pagemap
            for vma in vmas

                # Seek to the start address.
                seek(pagemap, vma.start * sizeof(UInt64))
                if eof(pagemap)
                    empty!(buffer)
                else
                    resize!(buffer, length(vma))
                    read!(pagemap, buffer)
                end

                # Call the passed function
                f(buffer)
            end
        end
    catch error
        # Check the error, if it's a "file not found (errnum=2)", throw a PID error to escape,
        if isa(error, SystemError) && error.errnum == 2
            throw(PIDException(pid))
        else
            rethrow(error)
        end
    end
    return nothing
end

"""
    markidle(pid, vmas)

Mark all of the memory pages in the list of `vmas` for process with `pid` as idle.
"""
function markidle(pid, vmas)
    open(IDLE_BITMAP, "w") do bitmap

        # Keep track of positions in the bitmap file that have already been written to.
        # Avoids reseeking and rewriting of positions already marked as idle.
        positions = Set{UInt64}()

        walkpagemap(pid, vmas) do pagemap_region
            # Iterate through each virtual to physical page mapping. If the page is
            # in memory, get the index of physical page and write 1's to it, marking it
            # as idle.
            #
            # Since the idle page buffer operates on 64 bit chunks, write 1's to all
            # 64 bits at a time - we don't really care about spilling into other processes.
            #
            # Also, keep a record of indices that have already been written to.
            # This REALLY speeds up this operation.
            for entry in pagemap_region
                if inmemory(entry)
                    pfn = pfnmask(entry)
                    pos = 8 * div64(pfn)

                    if !in(pos, positions)
                        # Mark this position as read
                        push!(positions, pos)

                        # Seek and write
                        seek(bitmap, pos)
                        write(bitmap, typemax(UInt64))
                    end
                end
            end
        end
    end
    return nothing
end

"""
    readidle(pid, vmas, buffer) -> SortedRangeVector{UInt}

Return the active pages within `vmas` of process with `pid`. Use `buffer` as storage for
the idle bitmap to avoid allocations
"""
function readidle(pid, vmas, buffer)
    pages = SortedRangeVector{UInt64}()
    # Read the whole idle bitmap buffer. This can take a while for systems with a large
    # amound of memory.
    read!(IDLE_BITMAP, buffer)

    # Index of the VMA currently being accessed.
    vma_index = 1

    walkpagemap(pid, vmas) do pagemap_region
        for (index, entry) in enumerate(pagemap_region)
            vma = vmas[vma_index]
            # Check if the active bit for this page is set. If so, add this frame's index
            # to the collection of active indices.
            if isactive(entry, buffer)
                # Convert to page number and add to pages
                pagenumber = (index - 1) + vma.start
                push!(pages, pagenumber)
            end
        end
        vma_index += 1
    end

    return pages
end