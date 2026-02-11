'use client'

import { useState } from 'react'
import { Geist } from 'next/font/google'
import { Analytics } from '@vercel/analytics/react'

const geist = Geist({ subsets: ['latin'] })

export default function Page() {
  const [email, setEmail] = useState('')
  const [name, setName] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [isSubmitted, setIsSubmitted] = useState(false)
  const [openFaq, setOpenFaq] = useState<number | null>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email || !name) return

    setIsSubmitting(true)
    try {
      await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email,
          name,
          productId: 'sitesnap'
        })
      })
      setIsSubmitted(true)
    } catch (error) {
      console.error('Error:', error)
    } finally {
      setIsSubmitting(false)
    }
  }

  const toggleFaq = (index: number) => {
    setOpenFaq(openFaq === index ? null : index)
  }

  return (
    <div className={`${geist.className} min-h-screen bg-slate-950 text-white`}>
      {/* Hero Section */}
      <section className="relative min-h-screen flex items-center justify-center px-4 overflow-hidden">
        {/* Background gradient */}
        <div className="absolute inset-0 bg-gradient-to-br from-blue-500/10 via-slate-950 to-purple-500/10"></div>
        
        {/* Glass morphism container */}
        <div className="relative z-10 max-w-4xl mx-auto text-center">
          <div className="backdrop-blur-sm bg-white/5 rounded-3xl p-8 md:p-12 border border-white/10">
            <h1 className="text-4xl md:text-6xl lg:text-7xl font-bold mb-6 bg-gradient-to-r from-white via-blue-100 to-blue-200 bg-clip-text text-transparent">
              SiteSnap
            </h1>
            <p className="text-xl md:text-2xl text-blue-200 mb-4 font-medium">
              Photo proof that saves your arse
            </p>
            <p className="text-lg md:text-xl text-slate-300 mb-12 max-w-2xl mx-auto leading-relaxed">
              Stop losing $15K arguments over "that crack wasn't there before". 
              Organise your site photos properly and pull evidence in seconds, not hours.
            </p>

            {/* Waitlist Form */}
            {!isSubmitted ? (
              <form onSubmit={handleSubmit} className="max-w-md mx-auto space-y-4">
                <input
                  type="text"
                  placeholder="Your name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  className="w-full px-6 py-4 rounded-xl bg-white/10 border border-white/20 text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent backdrop-blur-sm transition-all"
                  required
                />
                <input
                  type="email"
                  placeholder="Your email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full px-6 py-4 rounded-xl bg-white/10 border border-white/20 text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent backdrop-blur-sm transition-all"
                  required
                />
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="w-full bg-gradient-to-r from-blue-600 to-blue-500 hover:from-blue-500 hover:to-blue-400 px-8 py-4 rounded-xl font-semibold text-white transition-all duration-300 transform hover:scale-105 hover:shadow-xl hover:shadow-blue-500/25 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {isSubmitting ? 'Joining...' : 'Join the Waitlist'}
                </button>
              </form>
            ) : (
              <div className="max-w-md mx-auto p-6 rounded-xl bg-green-500/20 border border-green-500/30">
                <p className="text-green-300 font-semibold">✅ You're on the list!</p>
                <p className="text-slate-300 mt-2">We'll let you know when SiteSnap is ready.</p>
              </div>
            )}

            {/* Counter */}
            <div className="mt-8 text-slate-400">
              <span className="text-2xl font-bold text-blue-400">Early access</span> now open
            </div>
          </div>
        </div>
      </section>

      {/* Problem Section */}
      <section className="py-20 px-4">
        <div className="max-w-6xl mx-auto">
          <h2 className="text-3xl md:text-4xl font-bold text-center mb-4">
            Sound familiar?
          </h2>
          <p className="text-xl text-slate-400 text-center mb-16 max-w-2xl mx-auto">
            Every tradie has been here. These problems cost you time, money, and sleep.
          </p>

          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                emoji: "💸",
                title: "The $15K Argument",
                problem: "\"Client says crack wasn't there before. No proof. $15K argument.\""
              },
              {
                emoji: "📱",
                title: "The 2-Hour Scroll",
                problem: "\"Hundreds of site photos. Need THE one for a dispute. Scrolling camera roll for 2 hours.\""
              },
              {
                emoji: "🤦‍♂️",
                title: "The $25K Mistake",
                problem: "\"Apprentice forgot to photo waterproofing before tiler covered it. $25K he-said-she-said.\""
              }
            ].map((item, index) => (
              <div key={index} className="backdrop-blur-sm bg-white/5 rounded-2xl p-8 border border-white/10 hover:border-blue-500/30 transition-all duration-300 hover:transform hover:scale-105">
                <div className="text-4xl mb-4">{item.emoji}</div>
                <h3 className="text-xl font-semibold mb-4 text-blue-200">{item.title}</h3>
                <p className="text-slate-300 italic leading-relaxed">{item.problem}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Show Don't Tell Section */}
      <section className="py-20 px-4 bg-gradient-to-r from-slate-900/50 to-slate-800/50">
        <div className="max-w-6xl mx-auto">
          <h2 className="text-3xl md:text-4xl font-bold text-center mb-16">
            Before vs After
          </h2>

          <div className="grid lg:grid-cols-2 gap-12 items-center">
            {/* Before */}
            <div className="space-y-6">
              <div className="flex items-center gap-3 mb-6">
                <span className="text-2xl">😤</span>
                <h3 className="text-2xl font-bold text-red-400">Before: Camera Roll Chaos</h3>
              </div>
              
              <div className="backdrop-blur-sm bg-red-500/10 rounded-2xl p-6 border border-red-500/20">
                <div className="space-y-3">
                  <div className="flex items-center gap-3 p-3 bg-slate-800/50 rounded-lg">
                    <div className="w-12 h-12 bg-slate-700 rounded-lg flex items-center justify-center">📷</div>
                    <div className="flex-1">
                      <div className="text-sm text-slate-400">IMG_2847.jpg</div>
                      <div className="text-xs text-slate-500">Personal photo</div>
                    </div>
                  </div>
                  <div className="flex items-center gap-3 p-3 bg-slate-800/50 rounded-lg">
                    <div className="w-12 h-12 bg-slate-700 rounded-lg flex items-center justify-center">🏗️</div>
                    <div className="flex-1">
                      <div className="text-sm text-slate-400">IMG_2848.jpg</div>
                      <div className="text-xs text-slate-500">Some site photo?</div>
                    </div>
                  </div>
                  <div className="flex items-center gap-3 p-3 bg-slate-800/50 rounded-lg">
                    <div className="w-12 h-12 bg-slate-700 rounded-lg flex items-center justify-center">🍕</div>
                    <div className="flex-1">
                      <div className="text-sm text-slate-400">IMG_2849.jpg</div>
                      <div className="text-xs text-slate-500">Lunch</div>
                    </div>
                  </div>
                </div>
                
                <div className="mt-6 p-4 bg-slate-800/50 rounded-lg">
                  <div className="flex items-center gap-2 mb-2">
                    <span>🔍</span>
                    <span className="text-sm">Search: "waterproofing maple st"</span>
                  </div>
                  <div className="text-red-400 font-semibold">0 results found</div>
                </div>
              </div>
            </div>

            {/* After */}
            <div className="space-y-6">
              <div className="flex items-center gap-3 mb-6">
                <span className="text-2xl">✨</span>
                <h3 className="text-2xl font-bold text-green-400">After: SiteSnap Timeline</h3>
              </div>
              
              <div className="backdrop-blur-sm bg-green-500/10 rounded-2xl p-6 border border-green-500/20">
                <div className="mb-4">
                  <h4 className="font-semibold text-blue-300">42 Maple St Project</h4>
                </div>
                
                <div className="space-y-4">
                  <div className="border-l-2 border-blue-500 pl-4">
                    <div className="text-sm font-semibold text-blue-300">Waterproofing Stage</div>
                    <div className="text-xs text-slate-400 mb-2">4 photos • GPS verified • 15 Mar 2024</div>
                    <div className="grid grid-cols-2 gap-2">
                      <div className="bg-slate-800/50 rounded p-2 text-xs">
                        <div>📷 Pre-membrane</div>
                        <div className="text-slate-500">10:30 AM</div>
                      </div>
                      <div className="bg-slate-800/50 rounded p-2 text-xs">
                        <div>📷 Post-membrane</div>
                        <div className="text-slate-500">2:15 PM</div>
                      </div>
                    </div>
                  </div>
                  
                  <div className="border-l-2 border-slate-600 pl-4">
                    <div className="text-sm font-semibold text-slate-300">Frame Stage</div>
                    <div className="text-xs text-slate-400">12 photos • GPS verified • 22 Mar 2024</div>
                  </div>
                </div>
                
                <div className="mt-6 p-4 bg-slate-800/50 rounded-lg">
                  <div className="flex items-center gap-2 mb-2">
                    <span>🔍</span>
                    <span className="text-sm">Search: "waterproofing maple st"</span>
                  </div>
                  <div className="text-green-400 font-semibold">4 results found instantly</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-20 px-4">
        <div className="max-w-4xl mx-auto">
          <h2 className="text-3xl md:text-4xl font-bold text-center mb-16">
            How It Works
          </h2>

          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                step: "1",
                title: "Take Photos Normally",
                description: "Use your phone camera like always. No special process, no extra steps."
              },
              {
                step: "2",
                title: "Auto-Tags Everything",
                description: "SiteSnap automatically organises by project, date, GPS location, and construction stage."
              },
              {
                step: "3",
                title: "Pull Evidence in Seconds",
                description: "Search, filter, and export exactly what you need for disputes, reports, or client updates."
              }
            ].map((item, index) => (
              <div key={index} className="text-center">
                <div className="w-16 h-16 bg-gradient-to-r from-blue-600 to-blue-500 rounded-full flex items-center justify-center text-2xl font-bold mx-auto mb-6">
                  {item.step}
                </div>
                <h3 className="text-xl font-semibold mb-4 text-blue-200">{item.title}</h3>
                <p className="text-slate-300 leading-relaxed">{item.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-20 px-4 bg-gradient-to-r from-slate-900/50 to-slate-800/50">
        <div className="max-w-6xl mx-auto">
          <h2 className="text-3xl md:text-4xl font-bold text-center mb-16">
            Everything You Need
          </h2>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            {[
              {
                icon: "🏷️",
                title: "Auto-Tagging",
                description: "Automatically sorts photos by project, stage, and location"
              },
              {
                icon: "📅",
                title: "Evidence Timeline",
                description: "Chronological view of every stage with timestamps and GPS"
              },
              {
                icon: "⏰",
                title: "Hold Point Reminders",
                description: "Never forget to photo critical stages before they're covered"
              },
              {
                icon: "📊",
                title: "Instant Reports",
                description: "Generate professional reports with photos in minutes"
              },
              {
                icon: "👥",
                title: "Client Gallery",
                description: "Share progress photos with clients automatically"
              },
              {
                icon: "🏗️",
                title: "Multi-Site",
                description: "Manage unlimited projects from one dashboard"
              }
            ].map((feature, index) => (
              <div key={index} className="backdrop-blur-sm bg-white/5 rounded-2xl p-6 border border-white/10 hover:border-blue-500/30 transition-all duration-300">
                <div className="text-3xl mb-4">{feature.icon}</div>
                <h3 className="text-lg font-semibold mb-3 text-blue-200">{feature.title}</h3>
                <p className="text-slate-300">{feature.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="py-20 px-4">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-3xl md:text-4xl font-bold mb-16">
            Trusted by Aussie Tradies
          </h2>

          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                quote: "Saved my arse on a $30K waterproofing dispute. Had the photos timestamped and GPS-tagged. Client couldn't argue.",
                name: "Dave M.",
                role: "Builder, Sydney"
              },
              {
                quote: "No more scrolling through thousands of photos. Find what I need in seconds. Game changer.",
                name: "Sarah L.",
                role: "Site Supervisor, Melbourne"
              },
              {
                quote: "The hold point reminders are gold. Never miss photographing critical stages again.",
                name: "Tony R.",
                role: "Plumber, Brisbane"
              }
            ].map((testimonial, index) => (
              <div key={index} className="backdrop-blur-sm bg-white/5 rounded-2xl p-6 border border-white/10">
                <p className="text-slate-300 italic mb-4 leading-relaxed">"{testimonial.quote}"</p>
                <div className="text-blue-200 font-semibold">{testimonial.name}</div>
                <div className="text-slate-400 text-sm">{testimonial.role}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-20 px-4 bg-gradient-to-r from-slate-900/50 to-slate-800/50">
        <div className="max-w-3xl mx-auto">
          <h2 className="text-3xl md:text-4xl font-bold text-center mb-16">
            Common Questions
          </h2>

          <div className="space-y-4">
            {[
              {
                question: "How does the auto-tagging work?",
                answer: "SiteSnap uses your phone's GPS and our smart algorithms to automatically detect which project site you're at, what construction stage you're in, and organise photos accordingly. No manual tagging required."
              },
              {
                question: "What if I'm on a site with no internet?",
                answer: "No worries! SiteSnap works offline. Photos are tagged and organised locally, then synced when you're back online. Perfect for remote sites."
              },
              {
                question: "Can I use this for multiple projects?",
                answer: "Absolutely. SiteSnap handles unlimited projects and automatically keeps them separate. Perfect for builders juggling multiple sites."
              },
              {
                question: "How secure are my photos?",
                answer: "Your photos are encrypted and stored securely in Australia. Only you and people you specifically share with can access them. We take privacy seriously."
              },
              {
                question: "When will SiteSnap be available?",
                answer: "We're putting the finishing touches on SiteSnap now. Waitlist members get first access and early bird pricing when we launch."
              }
            ].map((faq, index) => (
              <div key={index} className="backdrop-blur-sm bg-white/5 rounded-2xl border border-white/10 overflow-hidden">
                <button
                  onClick={() => toggleFaq(index)}
                  className="w-full px-6 py-4 text-left flex items-center justify-between hover:bg-white/5 transition-colors"
                >
                  <span className="font-semibold text-blue-200">{faq.question}</span>
                  <span className={`transform transition-transform ${openFaq === index ? 'rotate-180' : ''}`}>
                    ▼
                  </span>
                </button>
                {openFaq === index && (
                  <div className="px-6 pb-4">
                    <p className="text-slate-300 leading-relaxed">{faq.answer}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="py-20 px-4">
        <div className="max-w-4xl mx-auto text-center">
          <div className="backdrop-blur-sm bg-white/5 rounded-3xl p-8 md:p-12 border border-white/10">
            <h2 className="text-3xl md:text-4xl font-bold mb-6">
              Stop Losing Money on Photo Disputes
            </h2>
            <p className="text-xl text-slate-300 mb-8 max-w-2xl mx-auto leading-relaxed">
              Join 1,247+ Australian tradies who are sick of camera roll chaos and expensive arguments.
            </p>
            
            {!isSubmitted ? (
              <form onSubmit={handleSubmit} className="max-w-md mx-auto space-y-4">
                <input
                  type="text"
                  placeholder="Your name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  className="w-full px-6 py-4 rounded-xl bg-white/10 border border-white/20 text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent backdrop-blur-sm transition-all"
                  required
                />
                <input
                  type="email"
                  placeholder="Your email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full px-6 py-4 rounded-xl bg-white/10 border border-white/20 text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent backdrop-blur-sm transition-all"
                  required
                />
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="w-full bg-gradient-to-r from-blue-600 to-blue-500 hover:from-blue-500 hover:to-blue-400 px-8 py-4 rounded-xl font-semibold text-white transition-all duration-300 transform hover:scale-105 hover:shadow-xl hover:shadow-blue-500/25 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {isSubmitting ? 'Joining...' : 'Get Early Access'}
                </button>
              </form>
            ) : (
              <div className="max-w-md mx-auto p-6 rounded-xl bg-green-500/20 border border-green-500/30">
                <p className="text-green-300 font-semibold">✅ You're on the list!</p>
                <p className="text-slate-300 mt-2">We'll let you know when SiteSnap is ready.</p>
              </div>
            )}
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-8 px-4 border-t border-white/10">
        <div className="max-w-6xl mx-auto text-center text-slate-400">
          <p>
            Built by{' '}
            <a 
              href="https://levasolutions.com.au" 
              target="_blank" 
              rel="noopener noreferrer"
              className="text-blue-400 hover:text-blue-300 transition-colors"
            >
              Leva Solutions
            </a>
          </p>
        </div>
      </footer>

      <Analytics />
    </div>
  )
}