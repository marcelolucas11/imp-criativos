using IMPCriativos.Core.Pipeline;
using Xunit;

namespace IMPCriativos.Tests;

/// <summary>Variações em paralelo com limite (1.0.0-beta.19). Porte de BoundedParallelTests.swift.</summary>
public class BoundedParallelTests
{
    private sealed class Probe
    {
        private readonly object _l = new();
        public int Running, Peak;
        public readonly List<int> Worked = new(), Followed = new();
        public void Start() { lock (_l) { Running++; Peak = Math.Max(Peak, Running); } }
        public void End(int i) { lock (_l) { Running--; Worked.Add(i); } }
        public void Follow(int i) { lock (_l) Followed.Add(i); }
    }

    private static Task FakeAI() => Task.Delay(Random.Shared.Next(2, 15));

    [Fact]
    public async Task EveryItemRunsExactlyOnceAndRespectsLimit()
    {
        var probe = new Probe();
        var items = Enumerable.Range(1, 50).ToList();
        await BoundedParallel.Run(items, 4, async i =>
        {
            probe.Start();
            await FakeAI();
            probe.End(i);
            return i % 7 == 0 ? null : (object?)i;
        }, f => { probe.Follow((int)f); return Task.CompletedTask; });
        Assert.Equal(items, probe.Worked.OrderBy(x => x));
        Assert.Equal(items.Where(x => x % 7 != 0), probe.Followed.OrderBy(x => x));
        Assert.True(probe.Peak <= 4);
        Assert.True(probe.Peak > 1);
    }

    [Fact]
    public async Task LimitChangesMidway()
    {
        var probe = new Probe();
        var dial = 5;
        await BoundedParallel.Run(Enumerable.Range(1, 40).ToList(), () => Task.FromResult(Volatile.Read(ref dial)), async i =>
        {
            probe.Start();
            if (i == 10) Volatile.Write(ref dial, 1);
            await FakeAI();
            probe.End(i);
            return (object?)null;
        }, _ => Task.CompletedTask);
        Assert.Equal(40, probe.Worked.Count);
    }

    [Fact]
    public async Task CancelStopsNewWorkAndKeepsNothingRunning()
    {
        var probe = new Probe();
        using var cts = new CancellationTokenSource();
        var task = BoundedParallel.Run(Enumerable.Range(1, 100).ToList(), 3, async i =>
        {
            probe.Start();
            await Task.Delay(20);
            probe.End(i);
            return (object?)i;
        }, f => { probe.Follow((int)f); return Task.CompletedTask; }, cts.Token);
        await Task.Delay(60);
        cts.Cancel();
        await task;
        Assert.True(probe.Worked.Count < 100);
        Assert.Equal(0, probe.Running);
    }

    [Fact]
    public async Task EmptyListReturns() =>
        await BoundedParallel.Run(new List<int>(), 2, _ => Task.FromResult<object?>(null), _ => Task.CompletedTask);
}
