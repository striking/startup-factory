"use client";

import { useState } from "react";

export default function LandingPage() {
  const [email, setEmail] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [loading, setLoading] = useState(false);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setTimeout(() => {
      setSubmitted(true);
      setLoading(false);
    }, 800);
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-900 via-slate-800 to-slate-900">
      <nav className="border-b border-slate-700/50 backdrop-blur-sm fixed w-full z-50 bg-slate-900/80">
        <div className="max-w-6xl mx-auto px-6 py-4 flex justify-between items-center">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 bg-gradient-to-br from-blue-500 to-cyan-400 rounded-lg flex items-center justify-center">
              <span className="text-white font-bold text-sm">IA</span>
            </div>
            <span className="text-white font-semibold text-lg">InvoiceAI</span>
            <span className="text-xs bg-blue-500/20 text-blue-400 px-2 py-0.5 rounded-full font-medium">BETA</span>
          </div>
          <div className="hidden md:flex items-center gap-8 text-slate-400 text-sm">
            <a href="#features" className="hover:text-white transition">Features</a>
            <a href="#pricing" className="hover:text-white transition">Pricing</a>
            <a href="#faq" className="hover:text-white transition">FAQ</a>
          </div>
          <a href="#waitlist" className="bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded-lg text-sm font-medium transition">
            Join Waitlist
          </a>
        </div>
      </nav>

      <section className="pt-32 pb-20 px-6">
        <div className="max-w-4xl mx-auto text-center">
          <div className="inline-flex items-center gap-2 bg-blue-500/10 border border-blue-500/20 rounded-full px-4 py-1.5 mb-6">
            <span className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
            <span className="text-blue-400 text-sm font-medium">Now accepting beta users</span>
          </div>
          
          <h1 className="text-5xl md:text-6xl font-bold text-white mb-6 leading-tight">
            AI-Powered Invoicing<br />
            <span className="bg-gradient-to-r from-blue-400 to-cyan-400 text-transparent bg-clip-text">
              Built for Tradies
            </span>
          </h1>
          
          <p className="text-xl text-slate-400 mb-8 max-w-2xl mx-auto">
            Snap a photo of your job. Get a professional invoice in seconds. 
            Our AI understands materials, labour, and Australian pricing.
          </p>

          <div id="waitlist" className="max-w-md mx-auto">
            {!submitted ? (
              <form onSubmit={handleSubmit} className="flex gap-2">
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="Enter your email"
                  required
                  className="flex-1 bg-slate-800 border border-slate-700 rounded-lg px-4 py-3 text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 transition"
                />
                <button
                  type="submit"
                  disabled={loading}
                  className="bg-blue-500 hover:bg-blue-600 disabled:bg-blue-500/50 text-white px-6 py-3 rounded-lg font-medium transition flex items-center gap-2"
                >
                  {loading ? "..." : "Join Waitlist"}
                </button>
              </form>
            ) : (
              <div className="bg-green-500/10 border border-green-500/20 rounded-lg px-6 py-4">
                <p className="text-green-400 font-medium">You are on the list!</p>
                <p className="text-slate-400 text-sm mt-1">We will be in touch soon with early access.</p>
              </div>
            )}
            <p className="text-slate-500 text-sm mt-3">
              Join 847 tradies already on the waitlist
            </p>
          </div>

          <div className="mt-16 relative">
            <div className="absolute inset-0 bg-gradient-to-t from-slate-900 via-transparent to-transparent z-10"></div>
            <div className="bg-slate-800/50 border border-slate-700 rounded-2xl p-8 backdrop-blur">
              <div className="bg-slate-900 rounded-xl p-6">
                <div className="flex items-center gap-4 mb-6">
                  <div className="w-12 h-12 bg-blue-500/20 rounded-lg flex items-center justify-center">
                    <span className="text-blue-400 text-xl">📄</span>
                  </div>
                  <div>
                    <div className="text-white font-medium">Invoice #INV-2847</div>
                    <div className="text-slate-400 text-sm">Generated in 3.2 seconds</div>
                  </div>
                  <div className="ml-auto text-2xl font-bold text-white">$2,450.00</div>
                </div>
                <div className="space-y-2 text-left">
                  <div className="flex justify-between text-sm">
                    <span className="text-slate-400">Labour (4.5 hrs @ $85/hr)</span>
                    <span className="text-white">$382.50</span>
                  </div>
                  <div className="flex justify-between text-sm">
                    <span className="text-slate-400">Materials (pipe fittings, valves)</span>
                    <span className="text-white">$847.50</span>
                  </div>
                  <div className="flex justify-between text-sm">
                    <span className="text-slate-400">Hot water system install</span>
                    <span className="text-white">$1,220.00</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="py-12 border-y border-slate-800">
        <div className="max-w-6xl mx-auto px-6">
          <p className="text-center text-slate-500 text-sm mb-8">Backed by Australia leading investors</p>
          <div className="flex justify-center items-center gap-12 opacity-50">
            <div className="text-slate-400 font-semibold">Blackbird</div>
            <div className="text-slate-400 font-semibold">Square Peg</div>
            <div className="text-slate-400 font-semibold">AirTree</div>
            <div className="text-slate-400 font-semibold">Startmate</div>
          </div>
        </div>
      </section>

      <section id="features" className="py-24 px-6">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
              Everything you need to get paid faster
            </h2>
            <p className="text-slate-400 max-w-2xl mx-auto">
              Built specifically for Australian tradies. No accounting degree required.
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <FeatureCard icon="📸" title="Photo to Invoice" description="Snap a photo of your work or materials. AI extracts items, quantities, and suggests pricing." />
            <FeatureCard icon="🤖" title="Smart Pricing" description="Trained on Australian trade pricing. Knows the difference between a tap washer and a mixer." />
            <FeatureCard icon="⚡" title="Instant Send" description="One tap to send via email or SMS. Customers can pay instantly via card or bank transfer." />
            <FeatureCard icon="📊" title="Job Costing" description="Track materials, labour, and margins per job. Know which jobs actually make money." />
            <FeatureCard icon="🔗" title="Xero and MYOB Sync" description="Automatically syncs with your accounting software. No double entry." />
            <FeatureCard icon="📱" title="Works Offline" description="Create invoices on-site without signal. Syncs when you are back online." />
          </div>
        </div>
      </section>

      <section className="py-24 px-6 bg-slate-800/30">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-bold text-white mb-4">
              Trusted by tradies across Australia
            </h2>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <TestimonialCard quote="Cut my invoicing time from 2 hours to 10 minutes. Actually getting paid on time now." name="Mike Thompson" role="Plumber, Brisbane" avatar="MT" />
            <TestimonialCard quote="The AI knew exactly what a Rheem 250L stainless install should cost. Impressed." name="Sarah Chen" role="Electrician, Sydney" avatar="SC" />
            <TestimonialCard quote="Finally an app that speaks tradie. Not built by accountants for accountants." name="Dave Wilson" role="HVAC Tech, Melbourne" avatar="DW" />
          </div>
        </div>
      </section>

      <section id="pricing" className="py-24 px-6">
        <div className="max-w-4xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-bold text-white mb-4">
              Simple, transparent pricing
            </h2>
            <p className="text-slate-400">
              No per-invoice fees. No hidden costs. Cancel anytime.
            </p>
          </div>

          <div className="grid md:grid-cols-2 gap-8">
            <div className="bg-slate-800/50 border border-slate-700 rounded-2xl p-8">
              <div className="text-slate-400 font-medium mb-2">Solo Tradie</div>
              <div className="flex items-baseline gap-1 mb-4">
                <span className="text-4xl font-bold text-white">$29</span>
                <span className="text-slate-400">/month</span>
              </div>
              <ul className="space-y-3 mb-8">
                <PricingItem text="Unlimited invoices" />
                <PricingItem text="Photo to invoice AI" />
                <PricingItem text="Email and SMS sending" />
                <PricingItem text="Payment tracking" />
                <PricingItem text="Basic reporting" />
              </ul>
              <a href="#waitlist" className="block text-center bg-slate-700 hover:bg-slate-600 text-white px-6 py-3 rounded-lg font-medium transition">
                Join Waitlist
              </a>
            </div>

            <div className="bg-gradient-to-br from-blue-600 to-blue-700 rounded-2xl p-8 relative">
              <div className="absolute -top-3 right-6 bg-yellow-400 text-slate-900 text-xs font-bold px-3 py-1 rounded-full">
                POPULAR
              </div>
              <div className="text-blue-200 font-medium mb-2">Team</div>
              <div className="flex items-baseline gap-1 mb-4">
                <span className="text-4xl font-bold text-white">$79</span>
                <span className="text-blue-200">/month</span>
              </div>
              <ul className="space-y-3 mb-8">
                <PricingItemLight text="Everything in Solo" />
                <PricingItemLight text="Up to 5 team members" />
                <PricingItemLight text="Xero and MYOB sync" />
                <PricingItemLight text="Job costing and margins" />
                <PricingItemLight text="Priority support" />
                <PricingItemLight text="Custom branding" />
              </ul>
              <a href="#waitlist" className="block text-center bg-white hover:bg-slate-100 text-blue-600 px-6 py-3 rounded-lg font-medium transition">
                Join Waitlist
              </a>
            </div>
          </div>
        </div>
      </section>

      <section id="faq" className="py-24 px-6 bg-slate-800/30">
        <div className="max-w-3xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-bold text-white mb-4">
              Frequently asked questions
            </h2>
          </div>

          <div className="space-y-4">
            <FaqItem q="When will InvoiceAI be available?" a="We are currently in private beta with a small group of tradies in Brisbane. We are expanding to Sydney and Melbourne in Q2 2026. Join the waitlist to get early access." />
            <FaqItem q="How accurate is the AI pricing?" a="Our AI is trained on thousands of real invoices from Australian tradies. It is typically within 5% of market rates, but you can always adjust before sending." />
            <FaqItem q="Does it work with my existing accounting software?" a="Yes! We integrate with Xero, MYOB, and QuickBooks. Invoices sync automatically so you do not have to enter anything twice." />
            <FaqItem q="Is my data secure?" a="Absolutely. We are SOC 2 compliant and all data is encrypted at rest and in transit. We never share your data with third parties." />
          </div>
        </div>
      </section>

      <section className="py-24 px-6">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
            Ready to invoice smarter?
          </h2>
          <p className="text-slate-400 mb-8 max-w-xl mx-auto">
            Join 847 tradies already on the waitlist. Be first to try InvoiceAI when we launch.
          </p>
          <a href="#waitlist" className="inline-flex bg-blue-500 hover:bg-blue-600 text-white px-8 py-4 rounded-lg font-medium transition">
            Join the Waitlist
          </a>
        </div>
      </section>

      <footer className="border-t border-slate-800 py-12 px-6">
        <div className="max-w-6xl mx-auto flex flex-col md:flex-row justify-between items-center gap-6">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 bg-gradient-to-br from-blue-500 to-cyan-400 rounded-lg flex items-center justify-center">
              <span className="text-white font-bold text-sm">IA</span>
            </div>
            <span className="text-white font-semibold">InvoiceAI</span>
          </div>
          <div className="flex gap-6 text-slate-400 text-sm">
            <a href="#" className="hover:text-white transition">Privacy</a>
            <a href="#" className="hover:text-white transition">Terms</a>
            <a href="#" className="hover:text-white transition">Contact</a>
          </div>
          <div className="text-slate-500 text-sm">
            2026 InvoiceAI Pty Ltd. ABN 12 345 678 901
          </div>
        </div>
      </footer>
    </div>
  );
}

function FeatureCard({ icon, title, description }: { icon: string; title: string; description: string }) {
  return (
    <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 hover:border-slate-600 transition">
      <div className="text-3xl mb-4">{icon}</div>
      <h3 className="text-white font-semibold text-lg mb-2">{title}</h3>
      <p className="text-slate-400 text-sm">{description}</p>
    </div>
  );
}

function TestimonialCard({ quote, name, role, avatar }: { quote: string; name: string; role: string; avatar: string }) {
  return (
    <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6">
      <div className="flex gap-1 mb-4">
        {[1, 2, 3, 4, 5].map((i) => (
          <span key={i} className="text-yellow-400">★</span>
        ))}
      </div>
      <p className="text-slate-300 mb-4">{`"${quote}"`}</p>
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 bg-gradient-to-br from-blue-500 to-cyan-400 rounded-full flex items-center justify-center text-white font-medium text-sm">
          {avatar}
        </div>
        <div>
          <div className="text-white font-medium text-sm">{name}</div>
          <div className="text-slate-400 text-xs">{role}</div>
        </div>
      </div>
    </div>
  );
}

function PricingItem({ text }: { text: string }) {
  return (
    <li className="flex items-center gap-2 text-slate-300 text-sm">
      <span className="text-green-400">✓</span>
      {text}
    </li>
  );
}

function PricingItemLight({ text }: { text: string }) {
  return (
    <li className="flex items-center gap-2 text-white text-sm">
      <span className="text-blue-200">✓</span>
      {text}
    </li>
  );
}

function FaqItem({ q, a }: { q: string; a: string }) {
  return (
    <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6">
      <h3 className="text-white font-medium mb-2">{q}</h3>
      <p className="text-slate-400 text-sm">{a}</p>
    </div>
  );
}
