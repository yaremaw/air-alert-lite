using System.Diagnostics;
using Godot;

/// Frame timings for the lite game: how long the sim and the map drawing
/// take on the CPU. Read by the stress stage of the screenshot run.
public static class LitePerf
{
	public static double SimMs, DrawMs, UiMs, UiProcMs;
	private static readonly Stopwatch Watch = Stopwatch.StartNew();

	public static double Now => Watch.Elapsed.TotalMilliseconds;

	public static void Reset() { SimMs = 0; DrawMs = 0; UiMs = 0; UiProcMs = 0; }

	public static string Monitors() =>
		$"draw calls {Performance.GetMonitor(Performance.Monitor.RenderTotalDrawCallsInFrame):0}, " +
		$"objects {Performance.GetMonitor(Performance.Monitor.RenderTotalObjectsInFrame):0}, " +
		$"primitives {Performance.GetMonitor(Performance.Monitor.RenderTotalPrimitivesInFrame):0}";
}
