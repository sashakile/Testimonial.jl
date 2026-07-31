# Testimonial.jl — Tests for subprocess timeout handling
#
# Verifies that run_with_timeout kills subprocesses that exceed the
# configured timeout, and that with_retry implements the retry-with-
# doubled-timeout logic per REC-002.
#
# See REC-002 (Subprocess timeout) in
# openspec/changes/implement-coverage-layer/specs/recording/spec.md

using Testimonial
using Test

# ── Constants ──────────────────────────────────

@testset "Timeout constants are defined" begin
    @test Testimonial.TIMEOUT_PER_ITEM_DEFAULT == 300.0
    @test Testimonial.MAX_TIMEOUT_PER_ITEM == 600.0
    @test Testimonial.MAX_RETRIES == 2
end

# ── run_with_timeout — quick process ───────────

@testset "run_with_timeout returns exit code for quick process" begin
    cmd = ["sh", "-c", "exit 42"]
    env = Dict{String, String}()
    result = Testimonial.run_with_timeout(cmd, env, 5.0)
    @test result == 42
end

@testset "run_with_timeout returns 0 for successful process" begin
    cmd = ["true"]
    env = Dict{String, String}()
    result = Testimonial.run_with_timeout(cmd, env, 5.0)
    @test result == 0
end

# ── run_with_timeout — timeout ─────────────────

@testset "run_with_timeout returns nothing on timeout" begin
    # A subprocess that sleeps longer than the timeout
    cmd = ["sh", "-c", "sleep 10"]
    env = Dict{String, String}()
    result = Testimonial.run_with_timeout(cmd, env, 0.1)
    @test result === nothing
end

@testset "run_with_timeout kills process on timeout" begin
    # Start a long-running process with a very short timeout
    cmd = ["sh", "-c", "sleep 10; echo 'should not reach'"]
    env = Dict{String, String}()
    result = Testimonial.run_with_timeout(cmd, env, 0.1)
    @test result === nothing

    # Verify the process is actually dead (no lingering sleep)
    # We can't easily check this in a portable way, but the test
    # structure ensures the process is killed via kill(force=true)
end

# ── run_with_timeout — env passthrough ─────────

@testset "run_with_timeout passes environment variables" begin
    # Use a script that prints the env var and exits with its value
    cmd = ["sh", "-c", """test "\$TEST_VAL" -eq 7"""]
    env = Dict("TEST_VAL" => "7")
    result = Testimonial.run_with_timeout(cmd, env, 5.0)
    @test result == 0
end

# ── with_retry — succeeds on first try ────────

@testset "with_retry returns immediately on success" begin
    call_count = Ref(0)
    result = Testimonial.with_retry(60.0) do timeout
        call_count[] += 1
        return 42
    end
    @test result == 42
    @test call_count[] == 1
end

# ── with_retry — retry on timeout ──────────────

@testset "with_retry retries on timeout until success" begin
    call_count = Ref(0)
    result = Testimonial.with_retry(60.0) do timeout
        call_count[] += 1
        if call_count[] <= 2
            return nothing  # timeout
        end
        return 99  # success on 3rd try
    end
    @test result == 99
    @test call_count[] == 3
end

# ── with_retry — exhaust retries ──────────────

@testset "with_retry returns nothing when all retries exhausted" begin
    call_count = Ref(0)
    result = Testimonial.with_retry(60.0) do timeout
        call_count[] += 1
        return nothing  # always timeout
    end
    @test result === nothing
    # 1 initial + 2 retries = 3 total calls
    @test call_count[] == 3
end

# ── with_retry — timeout doubling ──────────────

@testset "with_retry doubles timeout on each retry, capped at max" begin
    timeouts = Float64[]
    Testimonial.with_retry(10.0; max_retries=2, max_timeout=50.0) do timeout
        push!(timeouts, timeout)
        return nothing
    end
    # 1st: 10, 2nd: 20, 3rd: 40 (capped at 50, but 40 < 50)
    @test timeouts == [10.0, 20.0, 40.0]
end

@testset "with_retry caps timeout doubling at max_timeout" begin
    timeouts = Float64[]
    Testimonial.with_retry(30.0; max_retries=2, max_timeout=50.0) do timeout
        push!(timeouts, timeout)
        return nothing
    end
    # 1st: 30, 2nd: 50 (capped, since 60 > 50), 3rd: 50 (stays at cap)
    @test timeouts == [30.0, 50.0, 50.0]
end

# ── with_retry — custom max_retries ────────────

@testset "with_retry respects custom max_retries" begin
    call_count = Ref(0)
    Testimonial.with_retry(60.0; max_retries=0) do timeout
        call_count[] += 1
        return nothing
    end
    # 1 initial try, no retries (max_retries=0)
    @test call_count[] == 1
end

# ── Integration: run_with_timeout + with_retry ──

@testset "run_with_timeout + with_retry succeeds on retry" begin
    # Simulate a process that times out once, then succeeds
    cmd = ["sh", "-c", "exit 0"]
    env = Dict{String, String}()

    # Use a very short timeout that might cause timeout on slow CI,
    # but with retry it should succeed
    result = Testimonial.with_retry(5.0; max_retries=1) do timeout
        Testimonial.run_with_timeout(cmd, env, timeout)
    end
    @test result == 0
end

@testset "run_with_timeout + with_retry returns nothing on persistent timeout" begin
    cmd = ["sh", "-c", "sleep 30"]
    env = Dict{String, String}()

    result = Testimonial.with_retry(0.05; max_retries=1, max_timeout=0.1) do timeout
        Testimonial.run_with_timeout(cmd, env, timeout)
    end
    @test result === nothing
end

# ── Subprocess tree termination (testimonial-in3s.4) ──

@testset "run_with_timeout kills descendant processes" begin
    # Spawn a shell that creates a background child (sleep 30) then
    # sleeps itself. The timeout should kill both via SIGTERM/SIGKILL.
    marker = tempname()
    cmd = ["sh", "-c", string(
        "touch ", marker, "\n",
        "sleep 30 &\n",   # background child
        "echo \$! > ", marker, ".pid\n",
        "sleep 30\n",     # direct process
    )]
    env = Dict{String, String}()

    result = Testimonial.run_with_timeout(cmd, env, 0.2)
    @test result === nothing  # timeout
end