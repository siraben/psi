// Sakura — a native Haiku sumi-e artwork
#include <Application.h>
#include <Window.h>
#include <View.h>
#include <Bitmap.h>
#include <Font.h>
#include <Polygon.h>
#include <Region.h>
#include <math.h>
#include <stdint.h>

static uint32_t gSeed = 20260408u;
static float Rnd() { gSeed = gSeed * 1664525u + 1013904223u; return (gSeed >> 8) / 16777216.0f; }
static float Rr(float a, float b) { return a + (b - a) * Rnd(); }

struct Pt { float x, y; };
static const int kMaxBloom = 400;
static Pt gBloom[kMaxBloom];
static int gBloomCount = 0;

class SakuraView : public BView {
public:
	SakuraView(BRect r) : BView(r, "canvas", B_FOLLOW_ALL, B_WILL_DRAW), fArt(NULL)
	{
		SetViewColor(B_TRANSPARENT_COLOR);
		Render();
	}
	~SakuraView() { delete fArt; }

	void Draw(BRect) override { if (fArt) DrawBitmap(fArt, BPoint(0, 0)); }

private:
	BBitmap* fArt;

	void Alpha(BView* v) {
		v->SetDrawingMode(B_OP_ALPHA);
		v->SetBlendingMode(B_PIXEL_ALPHA, B_ALPHA_OVERLAY);
	}

	void Paper(BView* v, BRect b) {
		v->SetDrawingMode(B_OP_COPY);
		for (int y = 0; y <= (int)b.bottom; y += 2) {
			float t = y / b.bottom;
			rgb_color c = { (uint8)(248 - 6 * t), (uint8)(241 - 9 * t), (uint8)(222 - 14 * t), 255 };
			v->SetHighColor(c);
			v->FillRect(BRect(0, y, b.right, y + 1));
		}
		Alpha(v);
		// soft mottling
		for (int i = 0; i < 60; i++) {
			v->SetHighColor(Rnd() < 0.5 ? (rgb_color){255, 253, 244, 14} : (rgb_color){205, 185, 150, 6});
			BPoint c(Rr(0, b.right), Rr(0, b.bottom));
			float rr = Rr(20, 70);
			v->FillEllipse(c, rr, rr * Rr(0.5f, 1.0f));
		}
		// fibres
		v->SetPenSize(1);
		for (int i = 0; i < 260; i++) {
			float x = Rr(0, b.right), y = Rr(0, b.bottom);
			float a = Rr(0, 6.283f), len = Rr(6, 26);
			uint8 al = (uint8)Rr(18, 50);
			v->SetHighColor(Rnd() < 0.7 ? (rgb_color){170, 150, 115, al} : (rgb_color){255, 255, 248, (uint8)(al + 40)});
			BPoint p(x, y);
			for (int s = 0; s < 3; s++) {
				a += Rr(-0.5f, 0.5f);
				BPoint q(p.x + cosf(a) * len / 3, p.y + sinf(a) * len / 3);
				v->StrokeLine(p, q);
				p = q;
			}
		}
	}

	void Ground(BView* v) {
		Alpha(v);
		// distant hills
		for (int layer = 0; layer < 2; layer++) {
			uint8 al = layer == 0 ? 18 : 30;
			float base = layer == 0 ? 420 : 450;
			v->SetHighColor(70, 70, 75, al);
			BPolygon poly;
			poly.AddPoints(new BPoint(0, 520), 1);
			for (int x = 0; x <= 500; x += 10) {
				float y = base - 22 * sinf(x * 0.012f + layer * 2.1f) - 10 * sinf(x * 0.037f + layer);
				BPoint p(x, y);
				poly.AddPoints(&p, 1);
			}
			BPoint e(500, 520);
			poly.AddPoints(&e, 1);
			v->FillPolygon(&poly);
		}
		// dry-brush ground strokes
		v->SetLineMode(B_ROUND_CAP, B_ROUND_JOIN);
		for (int i = 0; i < 14; i++) {
			float x = Rr(-20, 330), y = Rr(478, 510), len = Rr(40, 130);
			v->SetPenSize(Rr(1, 3.5f));
			v->SetHighColor(40, 36, 34, (uint8)Rr(40, 110));
			v->StrokeLine(BPoint(x, y), BPoint(x + len, y + Rr(-4, 3)));
		}
		for (int i = 0; i < 18; i++) {
			float x = Rr(20, 300), y = Rr(485, 505);
			v->SetPenSize(1.2f);
			v->SetHighColor(40, 40, 30, 90);
			v->StrokeLine(BPoint(x, y), BPoint(x + Rr(-4, 4), y - Rr(5, 13)));
		}
	}

	void Branch(BView* v, float x, float y, float ang, float len, float w, int depth) {
		int segs = 6;
		float sl = len / segs;
		for (int i = 0; i < segs; i++) {
			ang += Rr(-0.18f, 0.18f);
			float nx = x + cosf(ang) * sl, ny = y + sinf(ang) * sl;
			float nw = w * 0.93f;
			// ink body with slight wet halo
			v->SetPenSize(nw + 3);
			v->SetHighColor(30, 26, 26, 35);
			v->StrokeLine(BPoint(x, y), BPoint(nx, ny));
			v->SetPenSize(nw);
			v->SetHighColor(22, 19, 20, 225);
			v->StrokeLine(BPoint(x, y), BPoint(nx, ny));
			// dry brush texture
			if (nw > 5) {
				v->SetPenSize(1);
				v->SetHighColor(90, 80, 70, 90);
				float px = -sinf(ang) * nw * 0.25f, py = cosf(ang) * nw * 0.25f;
				v->StrokeLine(BPoint(x + px, y + py), BPoint(nx + px, ny + py));
			}
			x = nx; y = ny; w = nw;
			if (depth > 0 && i >= 2 && Rnd() < 0.42f) {
				float side = Rnd() < 0.5f ? -1 : 1;
				Branch(v, x, y, ang + side * Rr(0.4f, 0.8f), len * Rr(0.45f, 0.7f), w * 0.62f, depth - 1);
			}
			if (depth <= 1 && Rnd() < 0.8f && gBloomCount < kMaxBloom)
				gBloom[gBloomCount++] = { x + Rr(-6, 6), y + Rr(-6, 6) };
		}
		if (depth > 0) {
			Branch(v, x, y, ang - Rr(0.25f, 0.6f), len * 0.68f, w * 0.7f, depth - 1);
			Branch(v, x, y, ang + Rr(0.25f, 0.6f), len * 0.6f, w * 0.62f, depth - 1);
		} else if (gBloomCount < kMaxBloom) {
			gBloom[gBloomCount++] = { x, y };
		}
	}

	void Petal(BView* v, BPoint c, float ang, float r) {
		BPoint pts[8];
		const float off[8][2] = { {0, 0}, {0.35f, -0.42f}, {0.8f, -0.4f}, {1.0f, -0.12f},
			{0.9f, 0.0f}, {1.0f, 0.12f}, {0.8f, 0.4f}, {0.35f, 0.42f} };
		float ca = cosf(ang), sa = sinf(ang);
		for (int i = 0; i < 8; i++) {
			float px = off[i][0] * r, py = off[i][1] * r;
			pts[i] = BPoint(c.x + px * ca - py * sa, c.y + px * sa + py * ca);
		}
		v->FillPolygon(pts, 8);
	}

	void Blossom(BView* v, BPoint c, float r) {
		float rot = Rr(0, 6.283f);
		uint8 g = (uint8)Rr(170, 200);
		v->SetHighColor(240, g, (uint8)(g + 20), 70);
		v->FillEllipse(c, r * 1.05f, r * 1.05f);
		for (int k = 0; k < 5; k++) {
			v->SetHighColor(248, (uint8)(g + 15), (uint8)(g + 30), 200);
			Petal(v, c, rot + k * 1.2566f, r);
		}
		v->SetHighColor(232, 120, 145, 150);
		v->FillEllipse(c, r * 0.3f, r * 0.3f);
		v->SetHighColor(150, 40, 60, 210);
		for (int k = 0; k < 5; k++) {
			float a = rot + 0.63f + k * 1.2566f;
			v->FillEllipse(BPoint(c.x + cosf(a) * r * 0.42f, c.y + sinf(a) * r * 0.42f), 0.9f, 0.9f);
		}
	}

	void Poetry(BView* v) {
		BFont f;
		if (f.SetFamilyAndStyle("Noto Serif CJK JP", "Regular") != B_OK)
			f = *be_plain_font;
		f.SetSize(56);
		v->SetFont(&f);
		v->SetDrawingMode(B_OP_ALPHA);
		v->SetBlendingMode(B_CONSTANT_ALPHA, B_ALPHA_OVERLAY);
		const char* col1[] = { "春", "風", "に" };
		const char* col2[] = { "桜", "舞", "う" };
		font_height fh; f.GetHeight(&fh);
		float step = 68;
		for (int i = 0; i < 3; i++) {
			v->SetHighColor(196, 45, 30, 235);
			float w1 = f.StringWidth(col1[i]);
			v->DrawString(col1[i], BPoint(448 - w1 / 2, 60 + fh.ascent * 0.85f + i * step));
			float w2 = f.StringWidth(col2[i]);
			v->DrawString(col2[i], BPoint(380 - w2 / 2, 100 + fh.ascent * 0.85f + i * step));
		}
		// seal
		Alpha(v);
		BRect s(431, 300, 465, 334);
		v->SetHighColor(190, 38, 28, 225);
		v->FillRoundRect(s, 4, 4);
		BFont sf(f); sf.SetSize(24);
		v->SetFont(&sf);
		v->SetHighColor(250, 238, 222, 255);
		v->DrawString("桜", BPoint(448 - sf.StringWidth("桜") / 2, 325));
		v->SetHighColor(250, 238, 222, 60);
		v->StrokeRoundRect(s.InsetByCopy(2, 2), 3, 3);
	}

	void Render() {
		BRect b = Bounds();
		fArt = new BBitmap(b, B_RGB32, true);
		BView* v = new BView(b, "off", B_FOLLOW_NONE, 0);
		fArt->AddChild(v);
		fArt->Lock();
		Paper(v, b);
		Ground(v);
		Alpha(v);
		v->SetLineMode(B_ROUND_CAP, B_ROUND_JOIN);
		// trunk rising from lower left, leaning right
		BRegion clip(BRect(0, 0, 342, b.bottom));
		clip.Include(BRect(342, 390, b.right, b.bottom));
		v->ConstrainClippingRegion(&clip);
		Branch(v, 150, 515, -1.62f, 120, 22, 3);
		Branch(v, 148, 410, -2.35f, 110, 11, 3);
		Branch(v, 152, 400, -0.55f, 120, 10, 3);
		Branch(v, 150, 360, -1.5f, 90, 9, 2);
		// blossoms
		for (int i = 0; i < gBloomCount; i++) {
			BPoint c = { gBloom[i].x, gBloom[i].y };
			if (c.x < 8 || c.y < 8 || (c.x > 336 && c.y < 390)) continue; // keep poem area clear
			Blossom(v, c, Rr(5, 9.5f));
			if (Rnd() < 0.35f)
				Blossom(v, BPoint(c.x + Rr(-10, 10), c.y + Rr(-10, 10)), Rr(4, 7));
		}
		// drifting petals
		for (int i = 0; i < 14; i++) {
			BPoint c(Rr(60, 340), Rr(260, 490));
			v->SetHighColor(245, 180, 196, (uint8)Rr(130, 200));
			Petal(v, c, Rr(0, 6.283f), Rr(6, 9));
		}
		v->ConstrainClippingRegion(NULL);
		Poetry(v);
		v->Sync();
		fArt->Unlock();
	}
};

class SakuraWindow : public BWindow {
public:
	SakuraWindow()
		: BWindow(BRect(700, 160, 1199, 679), "Sakura", B_TITLED_WINDOW,
			B_NOT_RESIZABLE | B_NOT_ZOOMABLE | B_QUIT_ON_WINDOW_CLOSE)
	{
		AddChild(new SakuraView(Bounds()));
	}
};

class SakuraApp : public BApplication {
public:
	SakuraApp() : BApplication("application/x-vnd.psi-sakura-fresh") {}
	void ReadyToRun() override { (new SakuraWindow())->Show(); }
};

int main() { SakuraApp app; app.Run(); return 0; }
