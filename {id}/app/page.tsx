"use client";

import { config } from "@/config";
import { useState } from "react";

const accent = config.accentColor;

/* ──────────────────── HERO ──────────────────── */
function Hero() {
  const [email, setEmail] = useState("");
  const [submitted, setSubmitted] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) return;
    if (config.waitlistAction) {
      try {
        await fetch(config.waitlistAction, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ email, product: config.name, ts: new Date().toISOString() }),
        });
      } catch {
        // silently handle — still show success
      }
    }
    setSubmitted(true);
    setEmail("");
  };

  return (
    <section className="flex flex-col items-center justify-center px-6 pt-28 pb-20 text-center">
      <h1 className="text-5xl font-extrabold tracking-tight sm:text-6xl lg:text-7xl max-w-4xl leading-tight">
        {config.name}
      </h1>
      <p className="mt-4 text-xl sm:text-2xl text-slate-300 max-w-2xl">
        {config.tagline}
      </p>
      <p className="mt-6 text-lg text-slate-400 max-w-xl leading-relaxed">
        {config.description}
      </p>

      {submitted ? (
        <div className="mt-10 rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-8 py-4 text-emerald-300 text-lg font-medium">
          ✅ You&apos;re on the list! We&apos;ll be in touch.
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="mt-10 flex flex-col sm:flex-row gap-3 w-full max-w-md">
          <input
            type="email"
            required
            placeholder="you@company.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="flex-1 rounded-lg border border-slate-700 bg-slate-900 px-5 py-3.5 text-white text-base placeholder-slate-500 focus:outline-none focus:ring-2"
            style={{ focusRingColor: accent } as React.CSSProperties}
          />
          <button
            type="submit"
            className="rounded-lg px-8 py-3.5 text-base font-bold text-white transition-all hover:brightness-110 cursor-pointer"
            style={{ backgroundColor: accent }}
          >
            Join Waitlist
          </button>
        </form>
      )}
      <p className="mt-4 text-sm text-slate-500">Free to join. No spam. Unsubscribe anytime.</p>
    </section>
  );
}

/* ──────────────────── PAIN POINTS ──────────────────── */
function PainPoints() {
  return (
    <section className="px-6 py-20 max-w-5xl mx-auto">
      <h2 className="text-3xl font-bold text-center mb-12">Sound familiar?</h2>
      <div className="grid md:grid-cols-3 gap-8">
        {config.painPoints.map((p, i) => (
          <div key={i} className="bg-slate-900/50 border border-slate-800 rounded-2xl p-8">
            <span className="text-4xl">{p.emoji}</span>
            <h3 className="text-xl font-bold mt-4 mb-3">{p.title}</h3>
            <p className="text-slate-400 text-base leading-relaxed">{p.desc}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ──────────────────── SOLUTION ──────────────────── */
function Solution() {
  return (
    <section className="px-6 py-20 max-w-3xl mx-auto text-center">
      <h2 className="text-3xl font-bold mb-6" style={{ color: accent }}>
        {config.solution.title}
      </h2>
      <p className="text-lg text-slate-300 leading-relaxed">{config.solution.desc}</p>
    </section>
  );
}

/* ──────────────────── FEATURES ──────────────────── */
function Features() {
  return (
    <section className="px-6 py-20 max-w-5xl mx-auto">
      <h2 className="text-3xl font-bold text-center mb-12">Everything you need</h2>
      <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-8">
        {config.features.map((f, i) => (
          <div key={i} className="bg-slate-900/50 border border-slate-800 rounded-2xl p-7">
            <div className="w-10 h-10 rounded-lg flex items-center justify-center text-white font-bold mb-4" style={{ backgroundColor: accent }}>
              {String(i + 1).padStart(2, "0")}
            </div>
            <h3 className="text-lg font-bold mb-2">{f.title}</h3>
            <p className="text-slate-400 text-base leading-relaxed">{f.desc}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ──────────────────── HOW IT WORKS ──────────────────── */
function HowItWorks() {
  return (
    <section className="px-6 py-20 max-w-4xl mx-auto">
      <h2 className="text-3xl font-bold text-center mb-12">How it works</h2>
      <div className="flex flex-col md:flex-row gap-8 md:gap-4">
        {config.howItWorks.map((s, i) => (
          <div key={i} className="flex-1 text-center">
            <div className="w-14 h-14 rounded-full flex items-center justify-center text-2xl font-extrabold mx-auto mb-5 text-white" style={{ backgroundColor: accent }}>
              {s.step}
            </div>
            <h3 className="text-xl font-bold mb-3">{s.title}</h3>
            <p className="text-slate-400 text-base leading-relaxed">{s.desc}</p>
            {i < config.howItWorks.length - 1 && (
              <div className="hidden md:block text-slate-600 text-3xl mt-4">→</div>
            )}
          </div>
        ))}
      </div>
    </section>
  );
}

/* ──────────────────── PRICING ──────────────────── */
function Pricing() {
  const tiers = [config.pricing.free, config.pricing.pro, config.pricing.business];
  return (
    <section className="px-6 py-20 max-w-5xl mx-auto">
      <h2 className="text-3xl font-bold text-center mb-4">Simple pricing</h2>
      <p className="text-center text-slate-400 mb-12 text-lg">Start free. Upgrade when you need more.</p>
      <div className="grid md:grid-cols-3 gap-8">
        {tiers.map((t, i) => {
          const isPro = i === 1;
          return (
            <div
              key={i}
              className={`rounded-2xl p-8 ${isPro ? "border-2 ring-1" : "border border-slate-800 bg-slate-900/50"}`}
              style={isPro ? { borderColor: accent, ringColor: accent, backgroundColor: "rgba(59,130,246,0.05)" } as React.CSSProperties : undefined}
            >
              {isPro && (
                <span className="inline-block text-xs font-bold uppercase tracking-wider px-3 py-1 rounded-full mb-4 text-white" style={{ backgroundColor: accent }}>
                  Most Popular
                </span>
              )}
              <h3 className="text-xl font-bold">{t.name}</h3>
              <div className="mt-3 mb-6">
                <span className="text-4xl font-extrabold">{t.price}</span>
                <span className="text-slate-400 text-base">{t.period}</span>
              </div>
              <ul className="space-y-3 mb-8">
                {t.features.map((f, j) => (
                  <li key={j} className="flex items-start gap-2 text-base text-slate-300">
                    <span className="mt-0.5" style={{ color: accent }}>✓</span>
                    {f}
                  </li>
                ))}
              </ul>
              <button
                className={`w-full rounded-lg py-3 font-bold text-base transition-all cursor-pointer ${isPro ? "text-white hover:brightness-110" : "border border-slate-600 text-slate-300 hover:border-slate-400"}`}
                style={isPro ? { backgroundColor: accent } : undefined}
              >
                {i === 0 ? "Get Started Free" : "Join Waitlist"}
              </button>
            </div>
          );
        })}
      </div>
    </section>
  );
}

/* ──────────────────── FAQ ──────────────────── */
function FAQ() {
  const [open, setOpen] = useState<number | null>(null);
  return (
    <section className="px-6 py-20 max-w-3xl mx-auto">
      <h2 className="text-3xl font-bold text-center mb-12">Questions?</h2>
      <div className="space-y-4">
        {config.faq.map((item, i) => (
          <div key={i} className="border border-slate-800 rounded-xl overflow-hidden">
            <button
              onClick={() => setOpen(open === i ? null : i)}
              className="w-full flex justify-between items-center px-6 py-5 text-left text-lg font-medium hover:bg-slate-900/50 transition-colors cursor-pointer"
            >
              {item.q}
              <span className="text-slate-500 text-xl ml-4">{open === i ? "−" : "+"}</span>
            </button>
            {open === i && (
              <div className="px-6 pb-5 text-slate-400 text-base leading-relaxed">{item.a}</div>
            )}
          </div>
        ))}
      </div>
    </section>
  );
}

/* ──────────────────── FOOTER ──────────────────── */
function Footer() {
  return (
    <footer className="border-t border-slate-800 px-6 py-10 text-center text-sm text-slate-500">
      <p>
        Built by{" "}
        <a href="https://levasolutions.com.au" className="underline hover:text-slate-300" target="_blank" rel="noopener noreferrer">
          Leva Solutions
        </a>{" "}
        — AI for the built world
      </p>
      <p className="mt-2">© {new Date().getFullYear()} {config.name}. All rights reserved.</p>
    </footer>
  );
}

/* ──────────────────── PAGE ──────────────────── */
export default function Home() {
  return (
    <main className="min-h-screen">
      <Hero />
      <PainPoints />
      <Solution />
      <Features />
      <HowItWorks />
      <Pricing />
      <FAQ />
      <Footer />
    </main>
  );
}
