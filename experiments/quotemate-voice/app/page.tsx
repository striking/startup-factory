"use client";

import { useState } from "react";

export default function Page() {
  const [email, setEmail] = useState("");
  const [isSubmitted, setIsSubmitted] = useState(false);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (email) {
      setIsSubmitted(true);
    }
  }

  return (
    <div className="min-h-screen bg-gray-900 text-white">
      <header className="border-b border-gray-800">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center">
              <div className="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center mr-3">
                <span className="text-white text-lg">🎤</span>
              </div>
              <span className="text-xl font-bold">QuoteMate</span>
              <span className="ml-2 px-2 py-0.5 text-xs bg-orange-500/20 text-orange-400 rounded-full">BETA</span>
            </div>
            <nav className="hidden md:flex space-x-8">
              <a href="#features" className="text-gray-300 hover:text-white transition-colors">Features</a>
              <a href="#pricing" className="text-gray-300 hover:text-white transition-colors">Pricing</a>
              <a href="#faq" className="text-gray-300 hover:text-white transition-colors">FAQ</a>
            </nav>
          </div>
        </div>
      </header>

      <section className="py-20 px-4 sm:px-6 lg:px-8">
        <div className="max-w-4xl mx-auto text-center">
          <div className="inline-flex items-center px-3 py-1 rounded-full text-sm bg-orange-500/10 text-orange-400 border border-orange-500/20 mb-8">
            <span className="w-2 h-2 bg-orange-400 rounded-full mr-2 animate-pulse"></span>
            Now accepting beta users
          </div>
          <h1 className="text-4xl md:text-6xl font-bold mb-6 leading-tight">
            Voice to Quote in
            <span className="text-orange-400"> Minutes</span>
          </h1>
          <p className="text-xl text-gray-300 mb-8 max-w-2xl mx-auto">
            Walk the job, dictate what you need, get a professional quote PDF. 
            Built for Australian electricians and plumbers who want to quote faster.
          </p>
          
          {!isSubmitted ? (
            <form onSubmit={handleSubmit} className="max-w-md mx-auto flex gap-4">
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="Enter your email"
                className="flex-1 px-4 py-3 rounded-lg bg-gray-800 border border-gray-700 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-orange-500"
                required
              />
              <button type="submit" className="px-6 py-3 bg-orange-500 text-white rounded-lg font-semibold hover:bg-orange-600 transition-colors">
                Join Waitlist
              </button>
            </form>
          ) : (
            <div className="max-w-md mx-auto p-4 bg-green-500/10 border border-green-500/20 rounded-lg">
              <p className="text-green-400">Thanks! We will be in touch soon.</p>
            </div>
          )}
          <p className="text-gray-500 text-sm mt-4">Join 200+ tradies already on the waitlist</p>
        </div>
      </section>

      <section className="py-20 px-4 sm:px-6 lg:px-8 bg-gray-800/50">
        <div className="max-w-6xl mx-auto">
          <h2 className="text-3xl md:text-4xl font-bold text-center mb-16">How It Works</h2>
          <div className="grid md:grid-cols-3 gap-8">
            <StepCard 
              step="1" 
              icon="🎤" 
              title="Record Voice Note" 
              description="Walk the job and dictate what materials and labour you need. Works on-site, even with patchy signal."
            />
            <StepCard 
              step="2" 
              icon="🤖" 
              title="AI Extracts Line Items" 
              description="Our AI converts your voice into professional line items with current Australian pricing."
            />
            <StepCard 
              step="3" 
              icon="📄" 
              title="Review and Send Quote" 
              description="Review the generated quote, make adjustments, and send a professional PDF instantly."
            />
          </div>
        </div>
      </section>

      <section id="features" className="py-20 px-4 sm:px-6 lg:px-8">
        <div className="max-w-6xl mx-auto">
          <h2 className="text-3xl md:text-4xl font-bold text-center mb-4">Everything You Need</h2>
          <p className="text-gray-400 text-center mb-16 max-w-2xl mx-auto">Built specifically for Australian tradies</p>
          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6">
            <FeatureCard icon="🎙️" title="Voice Input" description="Speak naturally. Our AI understands trade terminology and Aussie accents." />
            <FeatureCard icon="💰" title="Pricing Database" description="Up-to-date Australian pricing for electrical and plumbing materials." />
            <FeatureCard icon="📋" title="Quote Templates" description="Professional branded templates that help you win more work." />
            <FeatureCard icon="📤" title="Instant PDF Export" description="Generate and send quotes via email or SMS in one tap." />
          </div>
        </div>
      </section>

      <section className="py-20 px-4 sm:px-6 lg:px-8 bg-gray-800/50">
        <div className="max-w-4xl mx-auto">
          <h2 className="text-3xl font-bold text-center mb-12">What Tradies Are Saying</h2>
          <p className="text-center text-gray-500 text-sm mb-8">Illustrative examples based on beta feedback</p>
          <div className="grid md:grid-cols-2 gap-8">
            <TestimonialCard 
              quote="Used to spend Sunday afternoons doing quotes. Now I do them on-site in 5 minutes. Game changer."
              name="Example User"
              role="Electrician, Brisbane"
            />
            <TestimonialCard 
              quote="The voice recognition actually understands when I say Clipsal or Rheem. Finally, an app built for tradies."
              name="Example User"
              role="Plumber, Sydney"
            />
          </div>
        </div>
      </section>

      <section id="pricing" className="py-20 px-4 sm:px-6 lg:px-8">
        <div className="max-w-4xl mx-auto">
          <h2 className="text-3xl md:text-4xl font-bold text-center mb-4">Simple Pricing</h2>
          <p className="text-gray-400 text-center mb-12">No per-quote fees. Cancel anytime.</p>
          <div className="grid md:grid-cols-2 gap-8">
            <PricingCard 
              name="Solo"
              price="$29"
              description="For independent tradies"
              features={["Unlimited quotes", "Voice-to-quote AI", "Material pricing database", "PDF generation", "Email support"]}
            />
            <PricingCard 
              name="Team"
              price="$79"
              description="For growing businesses"
              features={["Everything in Solo", "Up to 5 team members", "Shared quote templates", "Quote analytics", "Priority support"]}
              highlighted
            />
          </div>
        </div>
      </section>

      <section id="faq" className="py-20 px-4 sm:px-6 lg:px-8 bg-gray-800/50">
        <div className="max-w-3xl mx-auto">
          <h2 className="text-3xl font-bold text-center mb-12">FAQ</h2>
          <div className="space-y-6">
            <FaqItem 
              question="When will QuoteMate be available?"
              answer="We are currently in private beta with a small group of tradies. Join the waitlist to get early access - we are adding new users every week."
            />
            <FaqItem 
              question="Does it work offline?"
              answer="You can record voice notes offline. They will process and generate quotes when you are back online."
            />
            <FaqItem 
              question="How accurate is the pricing?"
              answer="Our database includes current Australian pricing from major suppliers. You can always adjust prices before sending."
            />
          </div>
        </div>
      </section>

      <section className="py-20 px-4 sm:px-6 lg:px-8">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-3xl font-bold mb-4">Ready to Quote Faster?</h2>
          <p className="text-gray-400 mb-8">Join the waitlist and be first to try QuoteMate.</p>
          <a href="#" className="inline-block px-8 py-4 bg-orange-500 text-white rounded-lg font-semibold hover:bg-orange-600 transition-colors">
            Join the Waitlist
          </a>
        </div>
      </section>

      <footer className="border-t border-gray-800 py-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-6xl mx-auto flex flex-col md:flex-row justify-between items-center gap-6">
          <div className="flex items-center">
            <span className="text-lg mr-2">🎤</span>
            <span className="font-semibold">QuoteMate</span>
          </div>
          <div className="flex gap-6 text-gray-400 text-sm">
            <a href="#" className="hover:text-white">Privacy</a>
            <a href="#" className="hover:text-white">Terms</a>
            <a href="#" className="hover:text-white">Contact</a>
          </div>
          <p className="text-gray-500 text-sm">2026 QuoteMate. Built in Australia.</p>
        </div>
      </footer>
    </div>
  );
}

function StepCard({ step, icon, title, description }: { step: string; icon: string; title: string; description: string }) {
  return (
    <div className="text-center">
      <div className="w-16 h-16 bg-orange-500 rounded-full flex items-center justify-center mx-auto mb-6 text-2xl">
        {icon}
      </div>
      <h3 className="text-xl font-semibold mb-4">{title}</h3>
      <p className="text-gray-300">{description}</p>
    </div>
  );
}

function FeatureCard({ icon, title, description }: { icon: string; title: string; description: string }) {
  return (
    <div className="bg-gray-800 border border-gray-700 rounded-xl p-6 hover:border-gray-600 transition-colors">
      <div className="text-3xl mb-4">{icon}</div>
      <h3 className="text-lg font-semibold mb-2">{title}</h3>
      <p className="text-gray-400 text-sm">{description}</p>
    </div>
  );
}

function TestimonialCard({ quote, name, role }: { quote: string; name: string; role: string }) {
  return (
    <div className="bg-gray-800 border border-gray-700 rounded-xl p-6">
      <div className="flex gap-1 mb-4 text-yellow-400">
        {[1,2,3,4,5].map(i => <span key={i}>★</span>)}
      </div>
      <p className="text-gray-300 mb-4">{`"${quote}"`}</p>
      <div>
        <p className="font-medium">{name}</p>
        <p className="text-gray-500 text-sm">{role}</p>
      </div>
    </div>
  );
}

function PricingCard({ name, price, description, features, highlighted = false }: { name: string; price: string; description: string; features: string[]; highlighted?: boolean }) {
  return (
    <div className={`rounded-2xl p-8 ${highlighted ? "bg-orange-500 text-white" : "bg-gray-800 border border-gray-700"}`}>
      <h3 className={`font-medium mb-2 ${highlighted ? "text-orange-100" : "text-gray-400"}`}>{name}</h3>
      <div className="flex items-baseline gap-1 mb-2">
        <span className="text-4xl font-bold">{price}</span>
        <span className={highlighted ? "text-orange-200" : "text-gray-400"}>/month</span>
      </div>
      <p className={`mb-6 ${highlighted ? "text-orange-100" : "text-gray-400"}`}>{description}</p>
      <ul className="space-y-3 mb-8">
        {features.map((f, i) => (
          <li key={i} className="flex items-center gap-2 text-sm">
            <span className={highlighted ? "text-orange-200" : "text-green-400"}>✓</span>
            {f}
          </li>
        ))}
      </ul>
      <a href="#" className={`block text-center py-3 rounded-lg font-semibold transition-colors ${highlighted ? "bg-white text-orange-500 hover:bg-gray-100" : "bg-gray-700 hover:bg-gray-600"}`}>
        Join Waitlist
      </a>
    </div>
  );
}

function FaqItem({ question, answer }: { question: string; answer: string }) {
  return (
    <div className="bg-gray-800 border border-gray-700 rounded-xl p-6">
      <h3 className="font-semibold mb-2">{question}</h3>
      <p className="text-gray-400">{answer}</p>
    </div>
  );
}
