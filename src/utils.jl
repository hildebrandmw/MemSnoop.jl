#####
##### Utilities
#####

"""
In iterator that returns an infinite amount of `nothing`.
"""
struct Forever end

iterate(Forever, args...) = (nothing, nothing)
IteratorSize(::Forever) = IsInfinite()

"""
An iterator that stops iterating at a certain time.

**Example**
```
julia> using Dates

julia> y = SystemSnoop.Timeout(Second(10))
SystemSnoop.Timeout(2019-01-04T11:51:09.262)

julia> now()
2019-01-04T11:50:59.274

julia> for i in y; end

julia> now()
2019-01-04T11:51:09.275
```
"""
struct Timeout
    endtime::DateTime
end
Timeout(p::TimePeriod) = Timeout(now() + p)
iterate(T::Timeout, x...) = (now() >= T.endtime) ? nothing : (nothing, nothing)

#####
##### Pagemap Utilities
#####

"""
Exception indicating that process with `pid` no longer exists.
"""
struct PIDException <: Exception
    pid::Int64
end
PIDException() = PIDException(0)

#####
##### OS Utilities
#####

"""
    pause(pid)

Pause process with `pid`. If process does not exist, throw a [`PIDException`](@ref).
"""
function pause(pid)
    try
        run(`kill -STOP $pid`)
    catch error
        isa(error, ErrorException) ? throw(PIDException(pid)) : rethrow(error)
    end
    return nothing
end

"""
    resume(pid)

Resume process with `pid`. If process does not exist, throw a [`PIDException`](@ref)
"""
function resume(pid)
    try
        run(`kill -CONT $pid`)
    catch error
        isa(error, ErrorException) ? throw(PIDException(pid)) : rethrow(error)
    end
    return nothing
end

#####
##### pidsafe
#####

"""
    pidsafeopen(f::Function, file::String, pid, args...; kw...)

Open system pseudo file `file` for process with `pid` and pass the handle to `f`. If a
`File does not exist` error is thown, throws a `PIDException` instead.

Arguments `args` and `kw` are forwarded to the call to `open`.
"""
function pidsafeopen(f::Function, file::String, pid, args...; kw...)
    try
        open(file, args...; kw...) do handle
            f(handle)
        end
    catch error
        if isa(error, SystemError) && error.errnum == 2
            throw(PIDException(pid))
        else
            rethrow(error)
        end
    end
end

"""
    safeparse(::Type{T}, str; base = 10) -> T

Try to parse `str` to type `T`. If that fails, return `zero(T)`.
"""
function safeparse(::Type{T}, str; kw...) where {T}
    x = tryparse(T, str; kw...)
    return x === nothing ? zero(T) : x
end

"""
    isrunning(pid) -> Bool

Return `true` is a process with `pid` is running.
"""
isrunning(pid) = isdir("/proc/$pid")

#####
##### Sampler
#####

"""
    SystemSnoop.SmartSample(t::TimePeriod) -> SmartSample

Smart Sampler to ensure measurements happen every `t` time units. Samples will happen at
multiples of `t` from the first measurement. If a sample period is missed, the sampler will
wait until the next appropriate multiple of `t`.
"""
mutable struct SmartSample{T <: TimePeriod}
    initial::DateTime
    increment::T
    iteration::Int64
end

SmartSample(s::TimePeriod) = SmartSample(now(), s, 0)
function Base.sleep(s::SmartSample)
    # Initialize the sampler
    if s.iteration == 0
        s.initial = now()
        s.iteration = 1
    end

    # Compute the amount of time we need to sleep
    sleeptime = s.initial + (s.iteration * s.increment) - now()

    # In case measurements took longer than anticipated
    while sleeptime < zero(sleeptime)
        s.iteration += 1
        sleeptime = s.initial + (s.iteration * s.increment) - now()
    end
    sleep(sleeptime)
    s.iteration += 1
    return nothing
end

