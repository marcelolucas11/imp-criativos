using IMPCriativos.Core.Pipeline;
using Xunit;

namespace IMPCriativos.Tests;

/// <summary>Regras do Modo rápido com segurança (1.0.0-beta.19). Porte de SpeedPolicyTests.swift.</summary>
public class SpeedPolicyTests
{
    private static readonly DateTime T0 = DateTime.UnixEpoch.AddSeconds(1_000_000);

    private static void Warm(SpeedPolicy p, int count, DateTime at, double seconds = 40)
    {
        for (var i = 0; i < count; i++) p.RecordSuccess(seconds, at);
    }

    [Fact]
    public void StartsAtOriginalSpeed() => Assert.Equal(2, new SpeedPolicy(2, 5, true).Limit);

    [Fact]
    public void RaisesOneStepAtATimeUpToCeiling()
    {
        var p = new SpeedPolicy(2, 4, true);
        Warm(p, 3, T0);
        Assert.Equal(3, p.Limit);
        Warm(p, 3, T0);
        Assert.Equal(4, p.Limit);
        Warm(p, 10, T0);
        Assert.Equal(4, p.Limit);
    }

    [Fact]
    public void NeverRaisesWhenFastModeIsOff()
    {
        var p = new SpeedPolicy(2, 6, false);
        Warm(p, 20, T0);
        Assert.Equal(2, p.Limit);
    }

    [Fact]
    public void TroubleReturnsToOriginalAndHoldsForTenMinutes()
    {
        var p = new SpeedPolicy(2, 5, true);
        Warm(p, 6, T0);
        Assert.Equal(4, p.Limit);
        var change = p.RecordTrouble("IA ocupada (HTTP 503)", T0);
        Assert.Equal(SpeedChange.Lowered(2, "IA ocupada (HTTP 503)"), change);
        Assert.Equal(2, p.Limit);
        Assert.True(p.IsSafeMode(T0.AddSeconds(60)));
        Warm(p, 10, T0.AddMinutes(9));
        Assert.Equal(2, p.Limit);
        Warm(p, 3, T0.AddMinutes(11));
        Assert.Equal(3, p.Limit);
    }

    [Fact]
    public void RepeatedTroubleHoldsForThirtyMinutes()
    {
        var p = new SpeedPolicy(2, 5, true);
        p.RecordTrouble("429", T0);
        p.RecordTrouble("429", T0.AddSeconds(60));
        p.RecordTrouble("429", T0.AddSeconds(120));
        Assert.True(p.IsSafeMode(T0.AddMinutes(25)));
        Assert.Equal(SpeedPolicy.Risk.High, p.CurrentRisk(T0.AddSeconds(180)));
    }

    [Fact]
    public void StepsDownWhenMoreRequestsDoNotPayOff()
    {
        var p = new SpeedPolicy(2, 5, true);
        Warm(p, 3, T0, 40);
        Assert.Equal(3, p.Limit);
        for (var i = 0; i < 6; i++) p.RecordSuccess(80, T0);
        Assert.Equal(2, p.Limit);
    }

    [Fact]
    public void MacHoldKeepsOriginalSpeed()
    {
        var p = new SpeedPolicy(2, 5, true);
        Warm(p, 3, T0);
        Assert.Equal(3, p.Limit);
        Assert.Equal(SpeedChange.Lowered(2, "o computador está sem espaço"), p.SetMacHold("o computador está sem espaço"));
        Warm(p, 10, T0);
        Assert.Equal(2, p.Limit);
        Assert.Equal(SpeedPolicy.Risk.High, p.CurrentRisk(T0));
        p.SetMacHold(null);
        Warm(p, 3, T0);
        Assert.Equal(3, p.Limit);
    }

    [Fact]
    public void TurningFastModeOffDropsToOriginal()
    {
        var p = new SpeedPolicy(2, 5, true);
        Warm(p, 6, T0);
        Assert.Equal(4, p.Limit);
        p.Configure(2, 5, false);
        Assert.Equal(2, p.Limit);
        p.Configure(3, 2, true);
        Assert.Equal(3, p.Limit);
        Assert.Equal(3, p.Ceiling);
    }

    [Fact]
    public void LimitAlwaysWithinBounds()
    {
        var p = new SpeedPolicy(2, 6, true);
        var rng = new Random(1);
        var now = T0;
        for (var i = 0; i < 2000; i++)
        {
            now = now.AddSeconds(1 + rng.NextDouble() * 119);
            switch (rng.Next(10))
            {
                case 0: p.RecordTrouble("teste", now); break;
                case 1: p.SetMacHold(rng.Next(2) == 0 ? "quente" : null); break;
                default: p.RecordSuccess(10 + rng.NextDouble() * 190, now); break;
            }
            Assert.InRange(p.Limit, p.Base, p.Ceiling);
        }
    }
}
