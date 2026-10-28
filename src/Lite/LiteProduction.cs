using System.Collections.Generic;

/// One side's weapon production: a single queue that every factory works on
/// together, and the stockpile finished weapons go to. Weapons are made from
/// production points (PP), not bought with money; with nothing queued the
/// points are lost.
public sealed class LiteProduction
{
	public readonly List<LiteArm> Queue = new();
	public readonly int[] Stock = new int[3];
	/// PP put into the weapon at the head of the queue so far.
	public float Progress;
	/// PP a second, as of the last step.
	public float Rate;
	/// A finished weapon goes to the back of the queue again.
	public bool Repeat;

	public LiteProduction()
	{
		for (int i = 0; i < 3; i++) Stock[i] = LiteRules.StartStock((LiteArm)i);
	}

	public bool Idle => Queue.Count == 0;

	/// How far the weapon at the head of the queue is, 0 to 1.
	public float Share => Queue.Count > 0 ? Progress / LiteRules.PP(Queue[0]) : 0;

	/// PP still to go for everything queued.
	public float Pending
	{
		get
		{
			float sum = -Progress;
			foreach (var a in Queue) sum += LiteRules.PP(a);
			return sum;
		}
	}

	/// The stockpile's worth in PP.
	public float StockValue
	{
		get
		{
			float sum = 0;
			for (int i = 0; i < 3; i++) sum += Stock[i] * LiteRules.PP((LiteArm)i);
			return sum;
		}
	}

	public int Count(LiteArm a)
	{
		int n = 0;
		foreach (var q in Queue) if (q == a) n++;
		return n;
	}

	public int Add(LiteArm a, int n = 1)
	{
		int added = 0;
		while (added < n && Queue.Count < LiteRules.QueueMax) { Queue.Add(a); added++; }
		return added;
	}

	public void Clear()
	{
		Queue.Clear();
		Progress = 0;
	}

	/// Puts `pp` into the queue, head first; finished weapons go to the stock
	/// and are listed in `done`.
	public void Work(float pp, List<LiteArm> done)
	{
		while (Queue.Count > 0 && pp > 0)
		{
			var a = Queue[0];
			float need = LiteRules.PP(a) - Progress;
			if (pp < need) { Progress += pp; return; }
			pp -= need;
			Progress = 0;
			Queue.RemoveAt(0);
			Stock[(int)a]++;
			done.Add(a);
			if (Repeat) Queue.Add(a);
		}
	}

	/// Takes `n` weapons from the stock, if there are that many.
	public bool Take(LiteArm a, int n)
	{
		if (n <= 0 || Stock[(int)a] < n) return false;
		Stock[(int)a] -= n;
		return true;
	}
}
