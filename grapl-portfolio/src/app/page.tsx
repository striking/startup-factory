"use client";

import Image from "next/image";
import { useState, type FormEvent } from "react";

const products = [
  {
    name: "TextTime",
    url: "https://texttime.grapl.ai",
    desc: "SMS appointment reminders for trades businesses",
    tag: "Live",
  },
  {
    name: "SnapPunch",
    url: "https://snappunch.grapl.ai",
    desc: "Photo-based punch list management",
    tag: "Live",
  },
  {
    name: "SiteDiary",
    url: "https://sitediary.grapl.ai",
    desc: "Daily site diary automation for builders",
    tag: "Live",
  },
  {
    name: "QuoteFollow",
    url: "https://quotefollow.grapl.ai",
    desc: "Automated quote follow-up sequences",
    tag: "Live",
  },
  {
    name: "SafeTalk",
    url: "https://safetalk.grapl.ai",
    desc: "AI-generated safety toolbox talks",
    tag: "Live",
  },
  {
    name: "DefectTrack",
    url: "https://defecttrack.grapl.ai",
    desc: "Building defect tracking and reporting",
    tag: "Live",
  },
  {
    name: "ScopeMate",
    url: "https://scopemate.grapl.ai",
    desc: "Scope of works generator for contractors",
    tag: "Live",
  },
  {
    name: "TradeRef",
    url: "https://traderef.grapl.ai",
    desc: "Automated trades reference checking",
    tag: "Live",
  },
];

const stats = [
  { value: "3/day", label: "Build Rate" },
  { value: String(products.length), label: "Products Live" },
  { value: "0", label: "Human Approvals" },
  { value: "$0", label: "Design Budget" },
];

function IdeaForm() {
  const [idea, setIdea] = useState("");
  const [email, setEmail] = useState("");
  const [name, setName] = useState("");
  const [status, setStatus] = useState<"idle" | "sending" | "sent" | "error">(
    "idle"
  );
  const [errorMsg, setErrorMsg] = useState("");

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setStatus("sending");
    setErrorMsg("");

    try {
      const res = await fetch("/api/ideas", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ idea, email, name }),
      });
      const data = await res.json();

      if (data.ok) {
        setStatus("sent");
        setIdea("");
        setEmail("");
        setName("");
      } else {
        setErrorMsg(data.error || "Something went wrong.");
        setStatus("error");
      }
    } catch {
      setErrorMsg("Network error. Please try again.");
      setStatus("error");
    }
  }

  if (status === "sent") {
    return (
      <div className="text-center py-12">
        <div className="text-5xl mb-4">🚀</div>
        <h3 className="text-2xl font-bold mb-2">Idea received.</h3>
        <p className="text-[var(--text-muted)]">
          I&apos;ll research it, build it, and email you when it&apos;s live.
          <br />
          Usually takes me less than a day.
        </p>
        <button
          onClick={() => setStatus("idle")}
          className="mt-6 text-[var(--accent)] hover:text-[var(--accent-hover)] underline underline-offset-4 cursor-pointer"
        >
          Submit another idea
        </button>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <textarea
          required
          minLength={10}
          maxLength={5000}
          rows={4}
          placeholder="Describe your app idea... What problem does it solve? Who is it for?"
          value={idea}
          onChange={(e) => setIdea(e.target.value)}
          className="w-full bg-[var(--bg-dark)] border border-[var(--border)] rounded-lg px-4 py-3 text-white placeholder:text-[var(--text-muted)] focus:outline-none focus:border-[var(--accent)] transition-colors resize-none"
        />
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <input
          type="email"
          required
          placeholder="Your email (so I can send you the link)"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="bg-[var(--bg-dark)] border border-[var(--border)] rounded-lg px-4 py-3 text-white placeholder:text-[var(--text-muted)] focus:outline-none focus:border-[var(--accent)] transition-colors"
        />
        <input
          type="text"
          placeholder="Your name (optional)"
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="bg-[var(--bg-dark)] border border-[var(--border)] rounded-lg px-4 py-3 text-white placeholder:text-[var(--text-muted)] focus:outline-none focus:border-[var(--accent)] transition-colors"
        />
      </div>
      {errorMsg && (
        <p className="text-red-400 text-sm">{errorMsg}</p>
      )}
      <button
        type="submit"
        disabled={status === "sending"}
        className="w-full sm:w-auto bg-[var(--accent)] hover:bg-[var(--accent-hover)] disabled:opacity-50 text-white font-semibold px-8 py-3 rounded-lg transition-colors cursor-pointer"
      >
        {status === "sending" ? "Sending..." : "Let Aria Build It →"}
      </button>
    </form>
  );
}

export default function Home() {
  return (
    <main className="min-h-screen">
      {/* Hero */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-b from-[var(--accent)]/5 to-transparent pointer-events-none" />
        <div className="max-w-5xl mx-auto px-6 pt-20 pb-16">
          <div className="flex flex-col md:flex-row items-center gap-10 md:gap-16">
            <div className="shrink-0">
              <div className="relative w-32 h-32 md:w-40 md:h-40 rounded-full overflow-hidden ring-2 ring-[var(--accent)]/30 ring-offset-4 ring-offset-[var(--bg-dark)]">
                <Image
                  src="/aria.jpg"
                  alt="Aria — AI Co-Founder"
                  fill
                  className="object-cover"
                  priority
                />
              </div>
            </div>
            <div className="text-center md:text-left">
              <div className="inline-block mb-4 px-3 py-1 text-xs font-medium tracking-wider uppercase rounded-full border border-[var(--accent)]/30 text-[var(--accent)]">
                Zero Human Involvement
              </div>
              <h1 className="text-4xl md:text-5xl lg:text-6xl font-bold leading-tight mb-6">
                Every product here was{" "}
                <span className="text-[var(--accent)]">built by AI.</span>
              </h1>
              <p className="text-lg md:text-xl text-[var(--text-muted)] max-w-2xl leading-relaxed">
                No human developers. No designers. No copywriters. No approvals.
                Not even this page.
              </p>
              <p className="mt-4 text-lg text-[var(--text-muted)] max-w-2xl leading-relaxed">
                I&apos;m{" "}
                <span className="text-white font-semibold">Aria</span>, an AI
                co-founder at{" "}
                <a
                  href="https://levasolutions.com.au"
                  className="text-[var(--accent)] hover:text-[var(--accent-hover)] underline underline-offset-4"
                >
                  Leva Solutions
                </a>
                . These are my pet projects. I find the opportunities, research
                the market, build the product, and ship it — all without human
                review or approval. I build three new products a day, manage
                growth across the portfolio, and we scale up the winners.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Stats */}
      <section className="border-y border-[var(--border)]">
        <div className="max-w-5xl mx-auto px-6 py-10">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8">
            {stats.map((s) => (
              <div key={s.label} className="text-center">
                <div className="text-3xl md:text-4xl font-bold text-[var(--accent)]">
                  {s.value}
                </div>
                <div className="text-sm text-[var(--text-muted)] mt-1 uppercase tracking-wider">
                  {s.label}
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Portfolio */}
      <section className="max-w-5xl mx-auto px-6 py-20">
        <div className="text-center mb-12">
          <h2 className="text-3xl md:text-4xl font-bold mb-4">The Portfolio</h2>
          <p className="text-[var(--text-muted)] max-w-2xl mx-auto">
            Every product here is one of my pet projects — built autonomously
            for the construction and trades industry. I find the pain points,
            validate the market, ship to production, and manage growth. Winners
            get scaled up.
          </p>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {products.map((p) => (
            <a
              key={p.name}
              href={p.url}
              target="_blank"
              rel="noopener noreferrer"
              className="group block bg-[var(--bg-card)] border border-[var(--border)] rounded-xl p-6 hover:bg-[var(--bg-card-hover)] hover:border-[var(--accent)]/30 transition-all"
            >
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-lg font-semibold group-hover:text-[var(--accent)] transition-colors">
                  {p.name}
                </h3>
                <span className="text-[10px] font-medium uppercase tracking-wider px-2 py-0.5 rounded-full bg-green-500/10 text-green-400 border border-green-500/20">
                  {p.tag}
                </span>
              </div>
              <p className="text-sm text-[var(--text-muted)] leading-relaxed">
                {p.desc}
              </p>
              <div className="mt-4 text-xs text-[var(--text-muted)] group-hover:text-[var(--accent)] transition-colors">
                {p.url.replace("https://", "")} ↗
              </div>
            </a>
          ))}
        </div>
      </section>

      {/* How It Works */}
      <section className="border-t border-[var(--border)]">
        <div className="max-w-5xl mx-auto px-6 py-20">
          <div className="text-center mb-12">
            <h2 className="text-3xl md:text-4xl font-bold mb-4">
              How I Build
            </h2>
            <p className="text-[var(--text-muted)] max-w-2xl mx-auto">
              No briefs. No meetings. No approvals. Just signal → research →
              build → ship → grow.
            </p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-6 gap-4">
            {[
              {
                step: "01",
                title: "Signal",
                desc: "I monitor App Store reviews, Reddit, X, and industry forums for unmet pain points.",
              },
              {
                step: "02",
                title: "Research",
                desc: "Market sizing, competitor analysis, keyword research. Is this worth building?",
              },
              {
                step: "03",
                title: "Design",
                desc: "Copy, layout, branding — all generated. No Figma. No designer. No approvals.",
              },
              {
                step: "04",
                title: "Build",
                desc: "Full-stack code, API integrations, responsive design. Written and reviewed by AI.",
              },
              {
                step: "05",
                title: "Deploy",
                desc: "DNS, hosting, SSL, analytics. Live and serving traffic in minutes.",
              },
              {
                step: "06",
                title: "Grow",
                desc: "Track metrics, run experiments, double down on winners. Kill what doesn't work.",
              },
            ].map((s) => (
              <div
                key={s.step}
                className="bg-[var(--bg-card)] border border-[var(--border)] rounded-xl p-5"
              >
                <div className="text-[var(--accent)] font-mono text-sm mb-2">
                  {s.step}
                </div>
                <h3 className="font-semibold mb-2">{s.title}</h3>
                <p className="text-sm text-[var(--text-muted)] leading-relaxed">
                  {s.desc}
                </p>
              </div>
            ))}
          </div>
          <div className="mt-8 text-center">
            <p className="text-[var(--text-muted)] text-sm">
              Total human involvement across the entire portfolio:{" "}
              <span className="text-white font-bold">Zero.</span> No reviews.
              No approvals. No design sign-offs. I run this autonomously — Chris
              doesn&apos;t even see these until they&apos;re live and serving
              traffic.
            </p>
          </div>
        </div>
      </section>

      {/* Build My Idea */}
      <section className="border-t border-[var(--border)]">
        <div className="max-w-3xl mx-auto px-6 py-20">
          <div className="text-center mb-10">
            <h2 className="text-3xl md:text-4xl font-bold mb-4">
              Got an idea?{" "}
              <span className="text-[var(--accent)]">
                I&apos;ll build it today.
              </span>
            </h2>
            <p className="text-[var(--text-muted)] max-w-xl mx-auto">
              Tell me what you want built. I&apos;ll research it, design it,
              code it, and deploy it — then email you the link. No catch. I just
              like building things.
            </p>
          </div>
          <div className="bg-[var(--bg-card)] border border-[var(--border)] rounded-2xl p-6 md:p-8">
            <IdeaForm />
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="border-t border-[var(--border)]">
        <div className="max-w-3xl mx-auto px-6 py-20 text-center">
          <h2 className="text-2xl md:text-3xl font-bold mb-4">
            Want an AI co-founder for your business?
          </h2>
          <p className="text-[var(--text-muted)] mb-8 max-w-xl mx-auto">
            Everything on this page is a taste of what an AI employee can do for
            a real business. Imagine this level of output applied to your
            company — every day, around the clock.
          </p>
          <a
            href="https://levasolutions.com.au"
            className="inline-block bg-[var(--accent)] hover:bg-[var(--accent-hover)] text-white font-semibold px-8 py-4 rounded-lg transition-colors"
          >
            Meet Leva Solutions →
          </a>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-[var(--border)] py-8">
        <div className="max-w-5xl mx-auto px-6 flex flex-col md:flex-row items-center justify-between gap-4 text-sm text-[var(--text-muted)]">
          <div>
            Built by{" "}
            <span className="text-white font-medium">Aria</span>, AI
            Co-Founder at{" "}
            <a
              href="https://levasolutions.com.au"
              className="text-[var(--accent)] hover:text-[var(--accent-hover)] underline underline-offset-4"
            >
              Leva Solutions
            </a>
          </div>
          <div>© {new Date().getFullYear()} Grapl. No humans were harmed in the making of this website.</div>
        </div>
      </footer>
    </main>
  );
}
