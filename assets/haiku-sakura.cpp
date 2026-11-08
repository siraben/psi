// Sakura — a native Haiku sumi-e cherry blossom artwork.
#include <Application.h>
#include <Bitmap.h>
#include <Messenger.h>
#include <OS.h>
#include <Font.h>
#include <GradientRadial.h>
#include <Polygon.h>
#include <Shape.h>
#include <View.h>
#include <Window.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static const float kW = 500.0f;
static const float kH = 520.0f;
static const float kPi = 3.14159265f;
static const float kSS = 2.0f;
static const uint32 kMsgReady = 'rdy!';
static uint32 gTreeSeed = 1298;


// Loose, symmetric crown guide: a softly lobed dome spanning the paper.
static const float kDomeX = 226, kDomeY = 210, kDomeRX = 186, kDomeRY = 150;
static const float kDomeBottom = 350;

struct Rng {
	uint32 s;
	explicit Rng(uint32 seed) : s(seed * 2654435761u + 12345u) { if (!s) s = 1; }
	uint32 Next() { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return s; }
	float U() { return (Next() & 0xFFFFFF) / float(0x1000000); }
	float R(float a, float b) { return a + (b - a) * U(); }
};

static rgb_color C(int r, int g, int b, int a = 255)
{
	rgb_color c; c.red = r; c.green = g; c.blue = b; c.alpha = a; return c;
}

struct Branch {
	std::vector<BPoint> pts;
	std::vector<float> w;
	int depth;
};

struct Blossom {
	BPoint p;
	float r;
	float rot;
	int tone;
	bool back;
	bool bud;
};

struct Tree {
	std::vector<Branch> branches;
	std::vector<Blossom> blossoms;
	std::vector<BPoint> wash;
	int maxDepth;
	float lobe1, lobe2;
};

static float AngleLerp(float a, float target, float k)
{
	float d = target - a;
	while (d > kPi) d -= 2 * kPi;
	while (d < -kPi) d += 2 * kPi;
	return a + d * k;
}

class TreeBuilder {
public:
	TreeBuilder(uint32 seed, Tree& t) : rng(seed), tree(t) {}

	void AddBlossomCluster(BPoint c, float spread, int count, int depth)
	{
		for (int i = 0; i < count; i++) {
			float a = rng.R(0, 2 * kPi);
			float d = spread * sqrtf(rng.U());
			Blossom b;
			b.p = BPoint(c.x + cosf(a) * d, c.y + sinf(a) * d * 0.85f);
			b.back = rng.U() < 0.4f;
			b.r = b.back ? rng.R(3.4f, 5.4f) : rng.R(4.6f, 7.2f);
			if (!b.back && rng.U() < 0.14f) b.r = rng.R(7.4f, 9.0f);
			b.rot = rng.R(0, 2 * kPi);
			b.tone = int(rng.R(0, 4));
			b.bud = rng.U() < 0.04f;
			if (b.bud) b.r = std::min(b.r, 6.0f) * 0.5f;
			tree.blossoms.push_back(b);
			if (rng.U() < 0.55f)
				tree.wash.push_back(b.p);
		}
		(void)depth;
	}

	void Grow(BPoint p, float ang, float len, float w0, float w1, int depth)
	{
		Branch br;
		br.depth = depth;
		int n = std::max(5, int(len / 4.0f));
		float step = len / n;
		float curv = rng.R(-0.022f, 0.022f);
		float a = ang;
		for (int i = 0; i <= n; i++) {
			float t = float(i) / n;
			br.pts.push_back(p);
			br.w.push_back(w0 + (w1 - w0) * powf(t, 0.85f));
			a += curv + rng.R(-0.07f, 0.07f);
			// Gentle crown shaping: a lobed, irregular rounded silhouette.
			{
				float dx = (p.x - kDomeX) / kDomeRX, dy = (p.y - kDomeY) / kDomeRY;
				float d = sqrtf(dx * dx + dy * dy);
				float an = atan2f(dy, dx);
				float lobe = 0.88f + 0.10f * sinf(3 * an + tree.lobe1)
					+ 0.07f * sinf(5 * an + tree.lobe2);
				if (d > lobe && p.y < kDomeBottom) {
					float na = atan2f(dy / kDomeRY, dx / kDomeRX);
					if (cosf(a - na) > 0.0f) {
						float t1 = na + kPi / 2, t2 = na - kPi / 2;
						float tgt = cosf(a - t1) > cosf(a - t2) ? t1 : t2;
						a = AngleLerp(a, tgt, std::min(0.3f, (d - lobe) * 1.6f + 0.05f));
					}
				}
			}
			// Sakura limbs tend to spread outward rather than straight up.
			if (depth >= 2 && sinf(a) < -0.85f)
				a = AngleLerp(a, cosf(a) >= 0 ? -0.9f : -kPi + 0.9f, 0.05f);
			p.x += cosf(a) * step;
			p.y += sinf(a) * step;
		}
		tree.branches.push_back(br);

		int last = int(br.pts.size()) - 1;
		BPoint end = br.pts[last];
		float endAng = atan2f(br.pts[last].y - br.pts[last - 1].y,
			br.pts[last].x - br.pts[last - 1].x);

		// Blossoms along outer branches.
		if (depth >= 2) {
			float prob = depth >= tree.maxDepth - 2 ? 0.5f : 0.34f;
			for (int i = n / 4; i <= n; i += 2) {
				if (rng.U() < prob)
					AddBlossomCluster(br.pts[i], 9.0f + depth, 1 + int(rng.U() * 1.6f), depth);
			}
		}

		// Small side twigs give the silhouette its sumi-e rhythm.
		if (depth >= 2) {
			int twigs = int(rng.R(0, depth >= 3 ? 2.6f : 1.6f));
			for (int k = 0; k < twigs; k++) {
				int i = int(rng.R(n * 0.3f, n * 0.85f));
				float side = rng.U() < 0.5f ? -1.0f : 1.0f;
				float ta = AngleLerp(endAng, endAng + side * 1.0f, 1.0f) + rng.R(-0.2f, 0.2f);
				Twig(br.pts[i], ta, rng.R(12, 26), br.w[i] * 0.5f);
			}
		}

		if (depth >= tree.maxDepth) {
			AddBlossomCluster(end, 14.0f, int(rng.R(5, 9)), depth);
			return;
		}

		int kids = (depth == 0) ? 3 : (rng.U() < 0.4f ? 3 : 2);
		float spread = depth == 0 ? 0.78f : rng.R(0.32f, 0.52f);
		for (int k = 0; k < kids; k++) {
			float off;
			if (kids == 2) off = (k == 0 ? -1.0f : 1.0f) * spread * rng.R(0.7f, 1.1f);
			else off = (k - 1) * spread * rng.R(0.85f, 1.15f);
			bool main = (kids == 3 ? k == 1 : k == int(rng.U() * 2));
			float cl = len * (main ? rng.R(0.74f, 0.86f) : rng.R(0.6f, 0.76f));
			float cw0 = w1 * (main ? 0.92f : rng.R(0.6f, 0.78f));
			bool terminal = depth + 1 >= tree.maxDepth;
			float cw1 = terminal ? 0.55f : cw0 * 0.58f;
			Grow(end, endAng + off, cl, cw0, cw1, depth + 1);
		}
	}

	void Twig(BPoint p, float a, float len, float w0)
	{
		Branch br;
		br.depth = tree.maxDepth + 1;
		int n = std::max(4, int(len / 3.5f));
		float step = len / n;
		float curv = rng.R(-0.04f, 0.04f);
		for (int i = 0; i <= n; i++) {
			float t = float(i) / n;
			br.pts.push_back(p);
			br.w.push_back(std::max(0.45f, w0 * (1 - t) + 0.45f * t));
			a += curv;
			p.x += cosf(a) * step;
			p.y += sinf(a) * step;
		}
		tree.branches.push_back(br);
		AddBlossomCluster(p, 9.0f, int(rng.R(2, 5)), br.depth);
	}

	Rng rng;
	Tree& tree;
};


static void BuildTree(uint32 seed, Tree& t)
{
	t = Tree();
	t.maxDepth = 5;
	TreeBuilder b(seed, t);
	Rng& r = b.rng;
	t.lobe1 = r.R(0, 2 * kPi);
	t.lobe2 = r.R(0, 2 * kPi);
	// Trunk: a gently swaying S-curve, thick at the root.
	Branch trunk;
	trunk.depth = 0;
	BPoint p(214, 476);
	float a = -kPi / 2 - 0.06f;
	const int n = 24;
	const float len = 104;
	for (int i = 0; i <= n; i++) {
		float tt = float(i) / n;
		trunk.pts.push_back(p);
		trunk.w.push_back(30 - 13 * powf(tt, 0.8f));
		a += 0.018f * cosf(tt * kPi * 1.4f) + r.R(-0.03f, 0.03f);
		p.x += cosf(a) * len / n;
		p.y += sinf(a) * len / n;
	}
	t.branches.push_back(trunk);
	BPoint top = trunk.pts[n];
	// Scaffold limbs: designed fan with random detail.
	struct Limb { float at, ang, len, w0, w1; };
	Limb limbs[] = {
		{ 0.80f, -2.50f, 80, 11, 6.5f },
		{ 1.00f, -2.08f, 84, 14, 8 },
		{ 1.00f, -1.60f, 88, 15, 8.5f },
		{ 1.00f, -1.12f, 84, 13, 7.5f },
		{ 0.84f, -0.66f, 80, 10.5f, 6 },
	};
	for (const Limb& l : limbs) {
		int idx = int(l.at * n);
		BPoint start = l.at >= 1.0f ? top : trunk.pts[idx];
		b.Grow(start, l.ang + r.R(-0.12f, 0.12f), l.len * r.R(0.9f, 1.1f),
			l.w0, l.w1, 1);
	}
}

// Fit the whole tree inside the canvas with one uniform scale and
// translation (pivoting on the trunk base so it stays on the ground).
static void FitTreeToCanvas(Tree& t, float margin)
{
	float minX = 1e9, maxX = -1e9, minY = 1e9;
	for (const Branch& b : t.branches)
		for (size_t i = 0; i < b.pts.size(); i++) {
			float hw = b.w[i] * 0.5f;
			minX = std::min(minX, b.pts[i].x - hw);
			maxX = std::max(maxX, b.pts[i].x + hw);
			minY = std::min(minY, b.pts[i].y - hw);
		}
	for (const Blossom& b : t.blossoms) {
		minX = std::min(minX, b.p.x - b.r);
		maxX = std::max(maxX, b.p.x + b.r);
		minY = std::min(minY, b.p.y - b.r);
	}
	BPoint base = t.branches[0].pts[0];
	float s = 1.0f;
	s = std::min(s, (kW - 2 * margin) / (maxX - minX));
	s = std::min(s, (base.y - margin) / (base.y - minY));
	// Horizontal placement after scaling, kept within the margins.
	float nMinX = base.x + (minX - base.x) * s;
	float nMaxX = base.x + (maxX - base.x) * s;
	float dx = 0;
	if (nMinX + dx < margin) dx = margin - nMinX;
	if (nMaxX + dx > kW - margin) dx = (kW - margin) - nMaxX;
	auto map = [&](BPoint p) {
		return BPoint(base.x + (p.x - base.x) * s + dx, base.y + (p.y - base.y) * s);
	};
	for (Branch& b : t.branches) {
		for (size_t i = 0; i < b.pts.size(); i++) {
			b.pts[i] = map(b.pts[i]);
			b.w[i] *= s;
		}
	}
	for (Blossom& b : t.blossoms) {
		b.p = map(b.p);
		b.r *= s;
	}
	for (BPoint& p : t.wash) p = map(p);
	printf("sakura: fit scale %.3f shift %.1f (bbox %.0f..%.0f, top %.0f)\n",
		s, dx, minX, maxX, minY);
}

// ---------------------------------------------------------------------------

class ArtView : public BView {
public:
	ArtView(BRect frame);
	~ArtView() override;
	void AttachedToWindow() override;
	void Draw(BRect update) override;
	void Pulse() override;
	void MessageReceived(BMessage* msg) override;

private:
	static int32 RenderThread(void* data);
	void BuildAndRender();
	void RenderBase();
	void Downsample(BBitmap* hi, BBitmap* lo);
	void PaintPaperGrain(BBitmap* hi, Rng& r);
	void PaintWash(BBitmap* hi, Rng& r);
	void Compose();
	void DrawBackground(BView* v, Rng& r);
	void DrawGround(BView* v, Rng& r);
	void DrawBranch(BView* v, const Branch& b, Rng& r);
	void DrawRoots(BView* v, BPoint base, Rng& r);
	void DrawFlower(BView* v, const Blossom& b, float alphaScale);
	void StrokePetal(BView* v, BPoint c, float r, float a, rgb_color col);
	void DrawPetal(BView* v, BPoint c, float r, float a, rgb_color in, rgb_color out);
	void DrawPoem(BView* v);

	struct Drift { float x, y, vx, vy, rot, vr, phase, size, age, life; };
	void Respawn(Drift& d, bool initial);

	void RenderMask(int pass, std::vector<float>& out);
	void BuildPoemOverlay();

	BBitmap* fBase;
	BBitmap* fOverlay;
	BBitmap* fFrame;
	BView* fFrameView;
	Tree fTree;
	std::vector<Drift> fDrift;
	Rng fRng;
	float fTime;
	BMessenger fMessenger;
	thread_id fThread;
	std::atomic<bool> fReady;
	std::atomic<bool> fQuit;
};

ArtView::ArtView(BRect frame)
	: BView(frame, "art", B_FOLLOW_ALL, B_WILL_DRAW | B_PULSE_NEEDED),
	  fBase(NULL), fOverlay(NULL), fFrame(NULL), fFrameView(NULL), fRng(77), fTime(0),
	  fThread(-1), fReady(false), fQuit(false)
{
	SetViewColor(B_TRANSPARENT_COLOR);
	for (int i = 0; i < 7; i++) {
		Drift d;
		Respawn(d, true);
		fDrift.push_back(d);
	}
}

int32 ArtView::RenderThread(void* data)
{
	ArtView* view = (ArtView*)data;
	view->BuildAndRender();
	return 0;
}

void ArtView::BuildAndRender()
{
	bigtime_t t0 = system_time();
	BuildTree(gTreeSeed, fTree);
	FitTreeToCanvas(fTree, 15.0f);
	printf("sakura: tree seed %u branches %zu blossoms %zu (%.2fs)\n",
		(unsigned)gTreeSeed, fTree.branches.size(), fTree.blossoms.size(),
		(system_time() - t0) / 1e6);
	fflush(stdout);
	if (fQuit) return;
	RenderBase();
	if (fQuit) return;
	BuildPoemOverlay();
	if (fQuit) return;
	fMessenger.SendMessage(kMsgReady);
}

void ArtView::MessageReceived(BMessage* msg)
{
	if (msg->what == kMsgReady) {
		fReady = true;
		Compose();
		Invalidate();
		return;
	}
	BView::MessageReceived(msg);
}

ArtView::~ArtView()
{
	fQuit = true;
	if (fThread >= 0) {
		status_t st;
		wait_for_thread(fThread, &st);
	}
	delete fBase;
	delete fOverlay;
	delete fFrame;
}

void ArtView::Respawn(Drift& d, bool initial)
{
	// Petals leave the crown and drift down-left with the spring breeze.
	d.x = fRng.R(60, 440);
	d.y = initial ? fRng.R(150, 430) : fRng.R(170, 290);
	d.vx = fRng.R(-0.28f, -0.08f);
	d.vy = fRng.R(0.22f, 0.42f);
	d.rot = fRng.R(0, 2 * kPi);
	d.vr = fRng.R(-0.04f, 0.04f);
	d.phase = fRng.R(0, 2 * kPi);
	d.size = fRng.R(4.2f, 5.8f);
	d.life = fRng.R(500, 800);
	d.age = initial ? fRng.R(60, d.life * 0.6f) : 0;
}

void ArtView::AttachedToWindow()
{
	BRect b(0, 0, kW - 1, kH - 1);
	fBase = new BBitmap(b, B_RGBA32);
	fOverlay = new BBitmap(b, B_RGBA32);
	fFrame = new BBitmap(b, B_RGBA32, true);
	fFrameView = new BView(b, "frame", B_FOLLOW_NONE, B_WILL_DRAW);
	fFrame->AddChild(fFrameView);
	fMessenger = BMessenger(this);
	Window()->SetPulseRate(40000);
	fThread = spawn_thread(RenderThread, "sakura render", B_NORMAL_PRIORITY, this);
	if (fThread >= 0) resume_thread(fThread);
}

void ArtView::DrawBackground(BView* v, Rng& r)
{
	v->SetDrawingMode(B_OP_COPY);
	v->SetHighColor(C(246, 239, 224));
	v->FillRect(BRect(0, 0, kW, kH));
	v->SetDrawingMode(B_OP_ALPHA);
	v->SetBlendingMode(B_PIXEL_ALPHA, B_ALPHA_OVERLAY);

	// Gentle tonal clouds in the paper (soft round blooms, no patches).
	for (int i = 0; i < 70; i++) {
		BPoint c(r.R(-40, kW + 40), r.R(-40, kH + 40));
		float rad = r.R(40, 120);
		bool warm = r.U() < 0.6f;
		BGradientRadial g(c, rad);
		g.AddColor(warm ? C(226, 208, 178, 14) : C(255, 252, 244, 20), 0);
		g.AddColor(warm ? C(226, 208, 178, 0) : C(255, 252, 244, 0), 255);
		v->FillEllipse(c, rad, rad, g);
	}
	// Edge warmth via large radial bloom toward the corners.
	{
		BGradientRadial g(BPoint(kW / 2, kH / 2), 420);
		g.AddColor(C(200, 175, 140, 0), 0);
		g.AddColor(C(200, 175, 140, 0), 150);
		g.AddColor(C(190, 160, 120, 34), 255);
		v->FillEllipse(BPoint(kW / 2, kH / 2), 420, 420, g);
	}
	// Kozo fibres: thin wandering bezier strands.
	for (int i = 0; i < 520; i++) {
		BPoint p0(r.R(-20, kW + 20), r.R(-20, kH + 20));
		float a = r.R(0, 2 * kPi);
		float len = r.U() < 0.85f ? r.R(8, 34) : r.R(40, 90);
		BPoint p3(p0.x + cosf(a) * len, p0.y + sinf(a) * len);
		BPoint pts[4] = {
			p0,
			BPoint(p0.x + cosf(a + r.R(-0.8f, 0.8f)) * len * 0.35f,
				p0.y + sinf(a + r.R(-0.8f, 0.8f)) * len * 0.35f),
			BPoint(p3.x - cosf(a + r.R(-0.8f, 0.8f)) * len * 0.35f,
				p3.y - sinf(a + r.R(-0.8f, 0.8f)) * len * 0.35f),
			p3 };
		if (r.U() < 0.55f) v->SetHighColor(C(185, 160, 120, int(r.R(18, 42))));
		else v->SetHighColor(C(255, 253, 246, int(r.R(60, 120))));
		v->SetPenSize(r.R(0.4f, 1.0f));
		v->StrokeBezier(pts);
	}
	v->SetPenSize(1);
}

static void TaperStroke(BView* v, BPoint a, BPoint b, float bow, float w0, float w1,
	rgb_color col, Rng& r, bool dry)
{
	const int n = 28;
	BPoint left[n + 1], right[n + 1];
	float dx = b.x - a.x, dy = b.y - a.y;
	float len = sqrtf(dx * dx + dy * dy);
	float nx = -dy / len, ny = dx / len;
	for (int i = 0; i <= n; i++) {
		float t = float(i) / n;
		float off = bow * sinf(t * kPi);
		BPoint c(a.x + dx * t + nx * off, a.y + dy * t + ny * off);
		float w = (w0 + (w1 - w0) * t) * (0.4f + 0.6f * sinf(std::min(1.0f, t * 1.6f + 0.15f) * kPi * 0.5f));
		left[i] = BPoint(c.x + nx * w * 0.5f, c.y + ny * w * 0.5f);
		right[n - i] = BPoint(c.x - nx * w * 0.5f, c.y - ny * w * 0.5f);
	}
	BPoint poly[2 * n + 2];
	for (int i = 0; i <= n; i++) { poly[i] = left[i]; poly[n + 1 + i] = right[i]; }
	v->SetHighColor(col);
	v->FillPolygon(poly, 2 * n + 2);
	if (dry) {
		// Dry-brush streaks across the stroke.
		rgb_color paper = C(246, 239, 224, 150);
		v->SetHighColor(paper);
		for (int k = 0; k < 4; k++) {
			float f = r.R(-0.35f, 0.35f);
			float t0 = r.R(0.25f, 0.6f), t1 = std::min(1.0f, t0 + r.R(0.15f, 0.4f));
			BPoint p0(a.x + dx * t0 + nx * (bow * sinf(t0 * kPi) + f * w0),
				a.y + dy * t0 + ny * (bow * sinf(t0 * kPi) + f * w0));
			BPoint p1(a.x + dx * t1 + nx * (bow * sinf(t1 * kPi) + f * w1),
				a.y + dy * t1 + ny * (bow * sinf(t1 * kPi) + f * w1));
			v->SetPenSize(r.R(0.5f, 1.1f));
			v->StrokeLine(p0, p1);
		}
		v->SetPenSize(1);
	}
}

void ArtView::DrawGround(BView* v, Rng& r)
{
	// Pale watery ink pooled at the foot of the tree, built from many soft
	// round blooms so its edge stays organic.
	for (int i = 0; i < 70; i++) {
		float t = r.U();
		float x = 40 + t * 290;
		float y = 477 + sinf(t * kPi * 1.3f) * -2.0f + r.R(-2.5f, 2.5f);
		float fall = 1.0f - fabsf(x - 166) / 170.0f;
		float rad = r.R(7, 15) * (0.6f + 0.5f * fall);
		BGradientRadial g(BPoint(x, y), rad);
		g.AddColor(C(140, 132, 112, int(10 + 12 * fall)), 0);
		g.AddColor(C(140, 132, 112, 0), 255);
		v->FillEllipse(BPoint(x, y), rad, rad * 0.6f, g);
	}
	// Dry, hair-thin horizontal brush marks.
	for (int i = 0; i < 46; i++) {
		float cx = 166 + (r.U() + r.U() + r.U() - 1.5f) * 150;
		float len = r.R(14, 90);
		float y = r.R(471, 488);
		float tilt = r.R(-0.03f, 0.03f);
		BPoint p0(cx - len / 2, y - tilt * len / 2), p3(cx + len / 2, y + tilt * len / 2);
		BPoint pts[4] = { p0, BPoint(cx - len / 6, y + r.R(-1.5f, 1.5f)),
			BPoint(cx + len / 6, y + r.R(-1.5f, 1.5f)), p3 };
		float near = 1.0f - std::min(1.0f, fabsf(cx - 166) / 160.0f);
		v->SetHighColor(C(92, 86, 76, int(r.R(18, 40) + 45 * near)));
		v->SetPenSize(r.R(0.4f, 1.3f));
		v->StrokeBezier(pts);
	}
	v->SetPenSize(1);
	// Grass flicks.
	for (int i = 0; i < 14; i++) {
		float x = 166 + (r.U() + r.U() - 1.0f) * 130;
		float y = r.R(470, 480);
		float a = -kPi / 2 + r.R(-0.6f, 0.6f);
		float l = r.R(4, 10);
		TaperStroke(v, BPoint(x, y), BPoint(x + cosf(a) * l, y + sinf(a) * l),
			r.R(-1.2f, 1.2f), 1.4f, 0.3f, C(84, 88, 72, int(r.R(50, 100))), r, false);
	}
}

void ArtView::DrawRoots(BView* v, BPoint base, Rng& r)
{
	// Short surface roots reaching into the ground.
	TaperStroke(v, base + BPoint(-8, -2), base + BPoint(-34, 4), -1.5f, 7, 0.6f,
		C(44, 36, 34, 235), r, false);
	TaperStroke(v, base + BPoint(8, -2), base + BPoint(38, 3), 1.5f, 7, 0.6f,
		C(44, 36, 34, 235), r, false);
	TaperStroke(v, base + BPoint(2, 0), base + BPoint(-14, 6), 0.5f, 4, 0.5f,
		C(40, 32, 30, 200), r, false);
}

void ArtView::DrawBranch(BView* v, const Branch& b, Rng& r)
{
	size_t n = b.pts.size();
	if (n < 2) return;
	std::vector<BPoint> poly;
	std::vector<BPoint> right;
	std::vector<BPoint> normals(n);
	std::vector<float> hws(n);
	for (size_t i = 0; i < n; i++) {
		BPoint d = (i + 1 < n) ? b.pts[i + 1] - b.pts[i] : b.pts[i] - b.pts[i - 1];
		float l = sqrtf(d.x * d.x + d.y * d.y);
		if (l < 0.001f) l = 1;
		normals[i] = BPoint(-d.y / l, d.x / l);
	}
	for (size_t i = 0; i < n; i++) {
		float hw = b.w[i] * 0.5f;
		if (b.depth == 0) {
			// Smooth root flare.
			float t = float(i) / (n - 1);
			if (t < 0.22f) {
				float k = 1.0f - t / 0.22f;
				hw *= 1.0f + 0.62f * k * k;
			}
		}
		hws[i] = hw;
		poly.push_back(b.pts[i] + BPoint(normals[i].x * hw, normals[i].y * hw));
		right.push_back(b.pts[i] - BPoint(normals[i].x * hw, normals[i].y * hw));
	}
	float endW = b.w[n - 1];
	bool openEnd = endW > 1.2f;   // children continue from here
	if (!openEnd) {
		// Natural pointed tip.
		BPoint tipDir = b.pts[n - 1] - b.pts[n - 2];
		float tl = sqrtf(tipDir.x * tipDir.x + tipDir.y * tipDir.y);
		if (tl > 0) {
			float ext = std::max(1.6f, endW * 2.2f);
			poly.push_back(b.pts[n - 1] + BPoint(tipDir.x / tl * ext, tipDir.y / tl * ext));
		}
	}
	for (size_t i = right.size(); i-- > 0;) poly.push_back(right[i]);

	int depth = std::min(b.depth, 6);
	static const int tones[7][3] = {
		{64, 52, 49}, {62, 51, 48}, {66, 54, 50}, {72, 60, 55},
		{82, 68, 62}, {92, 78, 72}, {100, 86, 80} };
	v->SetHighColor(C(tones[depth][0], tones[depth][1], tones[depth][2], 255));
	v->FillPolygon(poly.data(), poly.size());
	// Rounded knuckles where limbs join and divide.
	if (b.depth > 0) {
		float bw = b.w[0] * 0.5f;
		v->FillEllipse(b.pts[0], bw, bw);
	}
	if (openEnd)
		v->FillEllipse(b.pts[n - 1], endW * 0.5f, endW * 0.5f);

	if (b.w[0] > 3.0f) {
		// Wet ink pooling down the shadow side.
		v->SetHighColor(C(24, 18, 17, 150));
		for (size_t i = 0; i + 1 < n; i++) {
			float o0 = hws[i] * 0.55f, o1 = hws[i + 1] * 0.55f;
			v->SetPenSize(std::max(0.6f, hws[i] * 0.7f));
			v->StrokeLine(b.pts[i] - BPoint(normals[i].x * o0, normals[i].y * o0),
				b.pts[i + 1] - BPoint(normals[i + 1].x * o1, normals[i + 1].y * o1));
		}
		// Dry-brush streaks on the lit side.
		int streaks = b.w[0] > 12 ? 5 : 2;
		for (int k = 0; k < streaks; k++) {
			float f = r.R(0.04f, 0.36f);
			v->SetHighColor(C(170, 154, 138, int(r.R(35, 75))));
			v->SetPenSize(r.R(0.4f, 1.0f));
			bool on = r.U() < 0.6f;
			for (size_t i = 0; i + 1 < n; i++) {
				if (r.U() < 0.2f) on = !on;
				if (!on) continue;
				float o0 = b.w[i] * f, o1 = b.w[i + 1] * f;
				v->StrokeLine(b.pts[i] + BPoint(normals[i].x * o0, normals[i].y * o0),
					b.pts[i + 1] + BPoint(normals[i + 1].x * o1, normals[i + 1].y * o1));
			}
		}
		// Horizontal lenticels typical of cherry bark.
		if (b.w[0] > 9) {
			for (size_t i = 3; i + 2 < n; i += 3) {
				if (r.U() < 0.5f) continue;
				float hw = b.w[i] * r.R(0.08f, 0.18f);
				float o = b.w[i] * r.R(-0.2f, 0.25f);
				BPoint c = b.pts[i] + BPoint(normals[i].x * o, normals[i].y * o);
				v->SetHighColor(C(150, 134, 118, int(r.R(45, 85))));
				v->SetPenSize(r.R(0.5f, 0.9f));
				v->StrokeLine(c - BPoint(normals[i].x * hw, normals[i].y * hw),
					c + BPoint(normals[i].x * hw, normals[i].y * hw));
			}
		}
		// Moss dots (tenten) along the limbs.
		int dots = int(b.w[0] / 3);
		for (int k = 0; k < dots; k++) {
			size_t i = size_t(r.R(0, n - 1));
			float o = hws[i] * r.R(0.8f, 1.05f) * (r.U() < 0.5f ? -1 : 1);
			BPoint c = b.pts[i] + BPoint(normals[i].x * o, normals[i].y * o);
			float s = r.R(0.7f, 1.6f);
			v->SetHighColor(C(30, 36, 26, int(r.R(150, 230))));
			v->FillEllipse(c, s, s * 0.8f);
		}
	}
	v->SetPenSize(1);
}

static void BuildPetal(BShape& s, BPoint c, float r, float a)
{
	float ux = cosf(a), uy = sinf(a);
	float vx = -uy, vy = ux;
	auto P = [&](float x, float y) {
		return BPoint(c.x + ux * y * r + vx * x * r, c.y + uy * y * r + vy * x * r);
	};
	s.MoveTo(P(0, 0.06f));
	BPoint c1[3] = { P(-0.56f, 0.22f), P(-0.56f, 0.84f), P(-0.17f, 1.0f) };
	s.BezierTo(c1);
	s.LineTo(P(0, 0.84f));
	s.LineTo(P(0.17f, 1.0f));
	BPoint c2[3] = { P(0.56f, 0.84f), P(0.56f, 0.22f), P(0, 0.06f) };
	s.BezierTo(c2);
	s.Close();
}

void ArtView::DrawPetal(BView* v, BPoint c, float r, float a, rgb_color in, rgb_color out)
{
	BShape s;
	BuildPetal(s, c, r, a);
	BGradientRadial g(c, r * 1.05f);
	g.AddColor(in, 0);
	g.AddColor(out, 255);
	v->MovePenTo(B_ORIGIN);
	v->FillShape(&s, g);
}

void ArtView::StrokePetal(BView* v, BPoint c, float r, float a, rgb_color col)
{
	BShape s;
	BuildPetal(s, c, r, a);
	v->SetHighColor(col);
	v->MovePenTo(B_ORIGIN);
	v->StrokeShape(&s);
}

void ArtView::DrawFlower(BView* v, const Blossom& b, float alphaScale)
{
	static const int pal[4][3] = {
		{252, 222, 230}, {250, 212, 224}, {254, 232, 236}, {246, 202, 216} };
	const int* pc = pal[b.tone & 3];
	int a = int(235 * alphaScale);
	if (b.bud) {
		v->SetHighColor(C(232, 138, 166, a));
		v->FillEllipse(b.p, b.r * 0.75f, b.r);
		v->SetHighColor(C(246, 186, 204, a));
		v->FillEllipse(b.p - BPoint(0.4f, 0.6f), b.r * 0.45f, b.r * 0.6f);
		return;
	}
	rgb_color in = C(240, 170, 192, a);
	rgb_color out = C(pc[0], pc[1], pc[2], a);
	if (b.back) {
		in = C(230, 162, 184, a);
		out = C(pc[0] - 10, pc[1] - 18, pc[2] - 12, a);
	}
	// All five petals as one shape: a single gradient fill per flower.
	BShape flower;
	for (int k = 0; k < 5; k++)
		BuildPetal(flower, b.p, b.r, b.rot + k * 2 * kPi / 5);
	BGradientRadial g(b.p, b.r * 1.05f);
	g.AddColor(in, 0);
	g.AddColor(out, 255);
	v->MovePenTo(B_ORIGIN);
	v->FillShape(&flower, g);
	if (!b.back && b.r > 5.6f) {
		// Hairline petal edges so each larger flower reads clearly.
		v->SetPenSize(0.5f);
		v->SetHighColor(C(226, 150, 176, 110));
		v->StrokeShape(&flower);
		v->SetPenSize(1);
	}
	// Heart of the flower.
	v->SetHighColor(C(226, 112, 146, int(190 * alphaScale)));
	v->FillEllipse(b.p, b.r * 0.15f, b.r * 0.15f);
	if (b.r > 6.0f && !b.back) {
		// Stamens and anthers, each batched into a single shape.
		BShape stamens, anthers;
		for (int k = 0; k < 7; k++) {
			float sa = b.rot + k * 2 * kPi / 7 + 0.3f;
			BPoint tip(b.p.x + cosf(sa) * b.r * 0.5f, b.p.y + sinf(sa) * b.r * 0.5f);
			stamens.MoveTo(b.p);
			stamens.LineTo(tip);
			if (k % 2 == 0) {
				const float d = 0.55f;
				anthers.MoveTo(tip + BPoint(0, -d));
				anthers.LineTo(tip + BPoint(d, 0));
				anthers.LineTo(tip + BPoint(0, d));
				anthers.LineTo(tip + BPoint(-d, 0));
				anthers.Close();
			}
		}
		v->SetPenSize(0.6f);
		v->SetHighColor(C(218, 120, 150, int(120 * alphaScale)));
		v->MovePenTo(B_ORIGIN);
		v->StrokeShape(&stamens);
		v->SetHighColor(C(200, 120, 100, int(170 * alphaScale)));
		v->FillShape(&anthers);
		v->SetPenSize(1);
	}
}

static bool FindSerifFont(BFont& font)
{
	if (font.SetFamilyAndStyle("Noto Serif CJK JP", "Regular") == B_OK)
		return true;
	// The face is installed per-user; load it directly if the font server
	// has not registered it yet.
	static const char* paths[] = {
		"/boot/home/config/non-packaged/data/fonts/otfonts/NotoSerifCJKjp-Regular.otf",
		"/boot/home/config/data/fonts/otfonts/NotoSerifCJKjp-Regular.otf",
		"/boot/system/non-packaged/data/fonts/otfonts/NotoSerifCJKjp-Regular.otf" };
	for (const char* path : paths)
		if (font.LoadFont(path) == B_OK)
			return true;
	int32 n = count_font_families();
	for (int32 i = 0; i < n; i++) {
		font_family fam;
		uint32 flags;
		if (get_font_family(i, &fam, &flags) != B_OK) continue;
		if (strstr(fam, "Serif") && strstr(fam, "CJK")
			&& (strstr(fam, "JP") || strstr(fam, "jp"))) {
			if (font.SetFamilyAndStyle(fam, "Regular") == B_OK) return true;
		}
	}
	return false;
}

void ArtView::DrawPoem(BView* v)
{
	// pass is encoded in the view's name: 0 = red ink coverage, 1 = seal glyph.
	int pass = strcmp(v->Name(), "mask1") == 0 ? 1 : 0;
	BFont font;
	bool ok = FindSerifFont(font);
	if (pass == 0) {
		font_family fam; font_style sty;
		font.GetFamilyAndStyle(&fam, &sty);
		printf("sakura: poem font %s / %s (%s)\n", fam, sty, ok ? "ok" : "fallback");
		fflush(stdout);
	}
	const float size = 50;
	font.SetSize(size);
	font_height fh;
	font.GetHeight(&fh);
	const float step = size * 1.1f;
	const float sx = 382, sy = 112 + 3 * step + 22;
	BRect seal(sx - 13, sy, sx + 13, sy + 26);

	if (pass == 0) {
		v->SetFont(&font);
		const char* col1[3] = { "春", "風", "に" };
		const char* col2[3] = { "桜", "舞", "う" };
		struct Col { const char** chars; float cx; float top; };
		Col cols[2] = { { col1, 444, 62 }, { col2, 382, 112 } };
		for (const Col& c : cols) {
			for (int i = 0; i < 3; i++) {
				float w = font.StringWidth(c.chars[i]);
				BPoint base(c.cx - w / 2, c.top + i * step + fh.ascent * 0.88f);
				v->SetHighColor(C(255, 255, 255));
				v->DrawString(c.chars[i], base);
			}
		}
		v->FillRoundRect(seal, 3.5f, 3.5f);
	} else {
		BFont sf(font);
		sf.SetSize(19);
		v->SetFont(&sf);
		float w = sf.StringWidth("桜");
		font_height sfh;
		sf.GetHeight(&sfh);
		v->SetHighColor(C(255, 255, 255));
		v->DrawString("桜", BPoint(sx - w / 2, sy + 13 + (sfh.ascent - sfh.descent) / 2 - 1));
	}
}

void ArtView::RenderMask(int pass, std::vector<float>& out)
{
	// Grey-scale coverage rendered at 2x, then filtered down. Averaging the
	// channels removes any subpixel colour fringes from the glyphs.
	BBitmap* hi = new BBitmap(BRect(0, 0, kW * kSS - 1, kH * kSS - 1), B_RGBA32, true);
	hi->Lock();
	BView* v = new BView(hi->Bounds(), pass ? "mask1" : "mask0", B_FOLLOW_NONE, B_WILL_DRAW);
	hi->AddChild(v);
	v->SetScale(kSS);
	v->SetHighColor(C(0, 0, 0));
	v->FillRect(BRect(0, 0, kW, kH));
	v->SetLowColor(C(0, 0, 0));
	v->SetDrawingMode(B_OP_OVER);
	DrawPoem(v);
	v->Sync();
	const uint8* src = (const uint8*)hi->Bits();
	int32 bpr = hi->BytesPerRow();
	int sw = int(kW * kSS), sh = int(kH * kSS);
	static const int wts[4] = { 1, 3, 3, 1 };
	out.assign(int(kW) * int(kH), 0.0f);
	for (int y = 0; y < int(kH); y++)
		for (int x = 0; x < int(kW); x++) {
			int acc = 0, wsum = 0;
			for (int j = 0; j < 4; j++) {
				int yy = std::min(sh - 1, std::max(0, y * 2 - 1 + j));
				for (int i = 0; i < 4; i++) {
					int xx = std::min(sw - 1, std::max(0, x * 2 - 1 + i));
					const uint8* px = src + yy * bpr + xx * 4;
					int w = wts[i] * wts[j];
					acc += (px[0] + px[1] + px[2]) * w;
					wsum += w * 3;
				}
			}
			out[y * int(kW) + x] = acc / (255.0f * wsum);
		}
	hi->RemoveChild(v);
	delete v;
	hi->Unlock();
	delete hi;
}

void ArtView::BuildPoemOverlay()
{
	std::vector<float> ink, glyph;
	RenderMask(0, ink);
	RenderMask(1, glyph);
	uint8* bits = (uint8*)fOverlay->Bits();
	int32 bpr = fOverlay->BytesPerRow();
	const float rr = 194, rg = 50, rb = 34;      // cinnabar
	const float ir = 248, ig = 238, ib = 222;    // ivory seal glyph
	Rng r(901);
	for (int y = 0; y < int(kH); y++)
		for (int x = 0; x < int(kW); x++) {
			float a = std::min(1.0f, ink[y * int(kW) + x] * 1.02f);
			float g = std::min(1.0f, glyph[y * int(kW) + x] * 1.05f);
			// Slight stamp-like irregularity in the ink.
			if (a > 0.0f && (r.Next() % 23) == 0) a *= 0.72f;
			uint8* px = bits + y * bpr + x * 4;
			px[0] = uint8(rb * (1 - g) + ib * g);
			px[1] = uint8(rg * (1 - g) + ig * g);
			px[2] = uint8(rr * (1 - g) + ir * g);
			px[3] = uint8(255 * a * 0.94f);
		}
}

void ArtView::RenderBase()
{
	// Render at 2x and filter down: smoother ink edges, softer petals and
	// no colour fringing from subpixel rasterisation.
	bigtime_t t0 = system_time();
	BBitmap* hi = new BBitmap(BRect(0, 0, kW * kSS - 1, kH * kSS - 1), B_RGBA32, true);
	hi->Lock();
	BView* v = new BView(hi->Bounds(), "base", B_FOLLOW_NONE, B_WILL_DRAW);
	hi->AddChild(v);
	v->SetScale(kSS);
	Rng r(2024);

	auto stage = [&](const char* name) {
		v->Sync();
		printf("sakura:   %-10s %.2fs\n", name, (system_time() - t0) / 1e6);
	};
	DrawBackground(v, r);
	v->Sync();
	PaintPaperGrain(hi, r);
	stage("paper");
	v->SetDrawingMode(B_OP_ALPHA);
	v->SetBlendingMode(B_PIXEL_ALPHA, B_ALPHA_OVERLAY);
	DrawGround(v, r);

	// Soft watercolour bloom so the canopy reads as one continuous cloud.
	v->Sync();
	PaintWash(hi, r);

	stage("wash");
	for (const Blossom& b : fTree.blossoms)
		if (b.back) DrawFlower(v, b, 0.85f);
	stage("back");

	// Branches: thickest first so twigs lie on top.
	std::vector<const Branch*> order;
	for (const Branch& b : fTree.branches) order.push_back(&b);
	std::stable_sort(order.begin(), order.end(),
		[](const Branch* a, const Branch* b) { return a->depth < b->depth; });
	DrawRoots(v, fTree.branches[0].pts[0], r);
	for (const Branch* b : order) DrawBranch(v, *b, r);
	stage("branches");

	for (const Blossom& b : fTree.blossoms)
		if (!b.back) DrawFlower(v, b, 1.0f);

	// A few fallen petals resting on the ground.
	for (int i = 0; i < 9; i++) {
		BPoint p(r.R(60, 320), r.R(474, 494));
		float rr = r.R(3.0f, 4.2f);
		DrawPetal(v, p, rr, r.R(-0.5f, 0.5f) + (r.U() < 0.5f ? 0 : kPi),
			C(238, 160, 184, 200), C(250, 214, 224, 200));
	}

	stage("front");
	v->Sync();
	stage("poem");
	Downsample(hi, fBase);
	hi->RemoveChild(v);
	delete v;
	hi->Unlock();
	delete hi;
	printf("sakura: rendered in %.2fs\n", (system_time() - t0) / 1e6);
	fflush(stdout);
}

void ArtView::PaintPaperGrain(BBitmap* hi, Rng& r)
{
	// Direct pixel work: fine grain, gentle mottling and tiny inclusions.
	uint8* bits = (uint8*)hi->Bits();
	int32 bpr = hi->BytesPerRow();
	int w = int(kW * kSS), h = int(kH * kSS);
	float ph1 = r.R(0, 6.28f), ph2 = r.R(0, 6.28f), ph3 = r.R(0, 6.28f);
	// Separable tables keep the mottling cheap to evaluate.
	std::vector<float> ax(w), bx(w), ay(h), by(h);
	for (int x = 0; x < w; x++) {
		ax[x] = sinf(x * 0.011f + ph1);
		bx[x] = sinf(x * 0.0047f + ph2);
	}
	for (int y = 0; y < h; y++) {
		ay[y] = sinf(y * 0.013f + ph3);
		by[y] = sinf(y * 0.0061f + ph1 * 0.5f);
	}
	uint32 seed = r.Next() | 1;
	for (int y = 0; y < h; y++) {
		uint8* row = bits + y * bpr;
		for (int x = 0; x < w; x++) {
			float m = 2.0f * ax[x] * ay[y] + 1.8f * bx[x] * by[y] + 0.9f * ax[x] * by[y];
			seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5;
			int d = int(m) + int(seed % 5) - 2;
			uint8* px = row + x * 4;
			px[0] = std::max(0, std::min(255, px[0] + d - 1));
			px[1] = std::max(0, std::min(255, px[1] + d));
			px[2] = std::max(0, std::min(255, px[2] + d));
		}
	}
	for (int i = 0; i < 3400; i++) {
		int x = int(r.R(0, w - 3)), y = int(r.R(0, h - 3));
		bool dark = r.U() < 0.55f;
		int size = r.U() < 0.2f ? 2 : 1;
		float a = dark ? r.R(0.08f, 0.22f) : r.R(0.2f, 0.45f);
		int tr = dark ? 150 : 255, tg = dark ? 126 : 253, tb = dark ? 96 : 246;
		for (int j = 0; j < size; j++)
			for (int k = 0; k < size; k++) {
				uint8* px = bits + (y + j) * bpr + (x + k) * 4;
				px[0] = uint8(px[0] * (1 - a) + tb * a);
				px[1] = uint8(px[1] * (1 - a) + tg * a);
				px[2] = uint8(px[2] * (1 - a) + tr * a);
			}
	}
}

void ArtView::PaintWash(BBitmap* hi, Rng& r)
{
	// Accumulate soft kernels and composite with a capped opacity, so the
	// crown becomes one continuous pink haze without blotchy build-up.
	int w = int(kW * kSS), h = int(kH * kSS);
	std::vector<float> acc(w * h, 0.0f);
	for (const BPoint& p : fTree.wash) {
		float rad = r.R(13, 21) * kSS;
		int cx = int(p.x * kSS), cy = int(p.y * kSS);
		int x0 = std::max(0, int(cx - rad)), x1 = std::min(w - 1, int(cx + rad));
		int y0 = std::max(0, int(cy - rad)), y1 = std::min(h - 1, int(cy + rad));
		float inv = 1.0f / (rad * rad);
		for (int y = y0; y <= y1; y++)
			for (int x = x0; x <= x1; x++) {
				float d2 = ((x - cx) * (x - cx) + (y - cy) * (y - cy)) * inv;
				if (d2 < 1.0f) {
					float k = 1.0f - d2;
					acc[y * w + x] += k * k;
				}
			}
	}
	uint8* bits = (uint8*)hi->Bits();
	int32 bpr = hi->BytesPerRow();
	const float pr = 241, pg = 176, pb = 196;
	for (int y = 0; y < h; y++) {
		uint8* row = bits + y * bpr;
		for (int x = 0; x < w; x++) {
			float v = acc[y * w + x];
			if (v <= 0.0f) continue;
			float a = 0.30f * (1.0f - expf(-v * 0.55f));
			uint8* px = row + x * 4;
			px[0] = uint8(px[0] * (1 - a) + pb * a);
			px[1] = uint8(px[1] * (1 - a) + pg * a);
			px[2] = uint8(px[2] * (1 - a) + pr * a);
		}
	}
}

void ArtView::Downsample(BBitmap* hi, BBitmap* lo)
{
	const uint8* src = (const uint8*)hi->Bits();
	uint8* dst = (uint8*)lo->Bits();
	int32 sbpr = hi->BytesPerRow(), dbpr = lo->BytesPerRow();
	int sw = int(kW * kSS), sh = int(kH * kSS);
	// Separable tent filter (taps 1-3-3-1) over the 2x grid.
	static const int wts[4] = { 1, 3, 3, 1 };
	for (int y = 0; y < int(kH); y++) {
		for (int x = 0; x < int(kW); x++) {
			int acc[3] = { 0, 0, 0 };
			int wsum = 0;
			for (int j = 0; j < 4; j++) {
				int sy = std::min(sh - 1, std::max(0, y * 2 - 1 + j));
				const uint8* row = src + sy * sbpr;
				for (int i = 0; i < 4; i++) {
					int sx = std::min(sw - 1, std::max(0, x * 2 - 1 + i));
					int w = wts[i] * wts[j];
					const uint8* px = row + sx * 4;
					acc[0] += px[0] * w; acc[1] += px[1] * w; acc[2] += px[2] * w;
					wsum += w;
				}
			}
			uint8* d = dst + y * dbpr + x * 4;
			d[0] = acc[0] / wsum; d[1] = acc[1] / wsum; d[2] = acc[2] / wsum; d[3] = 255;
		}
	}
}

void ArtView::Compose()
{
	if (!fFrame->Lock()) return;
	BView* v = fFrameView;
	v->SetDrawingMode(B_OP_COPY);
	v->DrawBitmap(fBase, B_ORIGIN);
	v->SetDrawingMode(B_OP_ALPHA);
	v->SetBlendingMode(B_PIXEL_ALPHA, B_ALPHA_OVERLAY);
	for (const Drift& d : fDrift) {
		float t = d.age / d.life;
		float alpha = std::min(1.0f, std::min(t * 6.0f, (1.0f - t) * 5.0f));
		if (alpha <= 0) continue;
		// Tumbling petal: foreshorten by flattening its width.
		float flip = 0.55f + 0.45f * fabsf(sinf(d.phase + fTime * 1.3f));
		float r = d.size;
		float a = d.rot;
		float ux = cosf(a), uy = sinf(a), vx = -uy, vy = ux;
		BPoint c(d.x, d.y);
		auto P = [&](float x, float y) {
			x *= flip;
			return BPoint(c.x + ux * (y - 0.5f) * r + vx * x * r,
				c.y + uy * (y - 0.5f) * r + vy * x * r);
		};
		BShape s;
		s.MoveTo(P(0, 0.0f));
		BPoint c1[3] = { P(-0.6f, 0.2f), P(-0.6f, 0.86f), P(-0.17f, 1.0f) };
		s.BezierTo(c1);
		s.LineTo(P(0, 0.84f));
		s.LineTo(P(0.17f, 1.0f));
		BPoint c2[3] = { P(0.6f, 0.86f), P(0.6f, 0.2f), P(0, 0.0f) };
		s.BezierTo(c2);
		s.Close();
		BGradientRadial g(P(0, 0), r);
		g.AddColor(C(236, 150, 178, int(220 * alpha)), 0);
		g.AddColor(C(252, 220, 230, int(220 * alpha)), 255);
		v->MovePenTo(B_ORIGIN);
		v->FillShape(&s, g);
	}
	// The poem is a transparent overlay drawn last, over tree and petals.
	v->DrawBitmap(fOverlay, B_ORIGIN);
	v->Sync();
	fFrame->Unlock();
}

void ArtView::Pulse()
{
	if (!fReady) return;
	fTime += 0.04f;
	for (Drift& d : fDrift) {
		d.age += 1;
		d.x += d.vx + 0.35f * sinf(fTime * 0.9f + d.phase);
		d.y += d.vy + 0.12f * cosf(fTime * 1.1f + d.phase);
		d.rot += d.vr + 0.01f * sinf(fTime + d.phase);
		if (d.age >= d.life || d.y > 480 || d.x < -10 || d.x > kW + 10)
			Respawn(d, false);
	}
	Compose();
	Invalidate();
}

void ArtView::Draw(BRect update)
{
	if (fReady) {
		DrawBitmap(fFrame, update, update);
	} else {
		SetHighColor(C(246, 239, 224));
		FillRect(update);
	}
}

// ---------------------------------------------------------------------------

class SakuraWindow : public BWindow {
public:
	SakuraWindow()
		: BWindow(BRect(700, 160, 1199, 679), "Sakura", B_TITLED_WINDOW,
			B_NOT_RESIZABLE | B_NOT_ZOOMABLE | B_QUIT_ON_WINDOW_CLOSE)
	{
		AddChild(new ArtView(Bounds()));
	}
};

class SakuraApp : public BApplication {
public:
	SakuraApp() : BApplication("application/x-vnd.psi-sakura-anthropic-high") {}
	void ReadyToRun() override
	{
		(new SakuraWindow())->Show();
	}
};

int main(int argc, char** argv)
{
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--seed") && i + 1 < argc)
			gTreeSeed = atoi(argv[++i]);
	}
	SakuraApp app;
	app.Run();
	return 0;
}
