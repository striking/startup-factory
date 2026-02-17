'use client'

import { useState } from 'react'
import { Geist } from 'next/font/google'
import { Analytics } from '@vercel/analytics/react'

const geist = Geist({ subsets: ['latin'] })

export default function Page() {
  const [email, setEmail] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [isSubmitted, setIsSubmitted] = useState(false)
  const [expandedFaq, setExpandedFaq] = useState<number | null>(null)

  // Waitlist API endpoint - deployed Google Apps Script web app
  const WAITLIST_API_URL = "/api/waitlist";

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email) return

    setIsSubmitting(true)

    try {
      // Get UTM params from URL
      const urlParams = new URLSearchParams(window.location.search);

      const response = await fetch(WAITLIST_API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email,
          product: 'traderef',
          referrer: document.referrer || '',
          utmSource: urlParams.get('utm_source') || '',
          utmMedium: urlParams.get('utm_medium') || '',
          utmCampaign: urlParams.get('utm_campaign') || ''
        })
      })

      if (response.ok) {
        setIsSubmitted(true)
        setEmail('')
      }
    } catch (error) {
      console.error('Submission error:', error)
    } finally {
      setIsSubmitting(false)
    }
  }

  const WaitlistForm = ({ showUrgency = false }: { showUrgency?: boolean }) => (
    <div className="w-full max-w-md mx-auto">
      {isSubmitted ? (
        <div className="text-center p-6 bg-emerald-500/10 border border-emerald-500/20 rounded-xl backdrop-blur-sm">
          <div className="text-2xl mb-2">✅</div>
          <p className="text-emerald-400 font-medium">You're on the list!</p>
          <p className="text-slate-400 text-sm mt-1">We'll send your invitation soon.</p>
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-4">
          {showUrgency && (
            <div className="text-center mb-4">
              <span className="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                🔥 Limited early access spots
              </span>
            </div>
          )}
          <div className="flex flex-col sm:flex-row gap-3">
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="your@email.com"
              required
              className="flex-1 px-4 py-3 bg-slate-800/50 border border-slate-700 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:border-transparent backdrop-blur-sm transition-all"
            />
            <button
              type="submit"
              disabled={isSubmitting}
              className="px-6 py-3 bg-gradient-to-r from-emerald-500 to-emerald-600 text-white font-medium rounded-lg hover:from-emerald-600 hover:to-emerald-700 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2 focus:ring-offset-slate-950 disabled:opacity-50 disabled:cursor-not-allowed transition-all transform hover:scale-105"
            >
              {isSubmitting ? 'Joining...' : 'Request Early Access'}
            </button>
          </div>
          <p className="text-xs text-slate-400 text-center">
            Invitation only. No spam, ever.
          </p>
        </form>
      )}
    </div>
  )

  return (
    <div className={`min-h-screen bg-slate-950 text-white ${geist.className}`}>
      {/* Navigation */}
      <nav className="border-b border-slate-800">
        <div className="max-w-6xl mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <div className="w-8 h-8 bg-gradient-to-br from-emerald-500 to-emerald-600 rounded-lg flex items-center justify-center">
                <span className="text-white font-bold text-sm">TR</span>
              </div>
              <span className="font-semibold">TradeRef</span>
            </div>
            
            <div className="hidden md:flex items-center space-x-6">
              <a 
                href="/electrician-salary" 
                className="text-slate-300 hover:text-emerald-400 transition-colors font-medium"
              >
                Electrician Salaries
              </a>
              <a 
                href="#waitlist" 
                className="px-4 py-2 bg-gradient-to-r from-emerald-500 to-emerald-600 text-white font-medium rounded-lg hover:from-emerald-600 hover:to-emerald-700 transition-all"
              >
                Get Early Access
              </a>
            </div>
            
            {/* Mobile menu button */}
            <button className="md:hidden text-slate-300">
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
              </svg>
            </button>
          </div>
        </div>
      </nav>

      {/* Hero Section */}
      <section id="waitlist" className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-emerald-500/5 via-transparent to-slate-950"></div>
        <div className="relative max-w-6xl mx-auto px-4 py-20 sm:py-32">
          <div className="text-center space-y-8">
            <div className="space-y-4">
              <div className="inline-flex items-center px-4 py-2 rounded-full text-sm font-medium bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 backdrop-blur-sm">
                🚀 Now in private beta
              </div>
              <h1 className="text-4xl sm:text-6xl lg:text-7xl font-bold tracking-tight">
                Verified trade references
                <span className="block text-transparent bg-clip-text bg-gradient-to-r from-emerald-400 to-emerald-600">
                  in 60 seconds
                </span>
              </h1>
              <p className="text-xl sm:text-2xl text-slate-300 max-w-3xl mx-auto leading-relaxed">
                Stop chasing old clients for references. Build trust with verified reviews that actually mean something.
              </p>
            </div>
            
            <WaitlistForm />
            
            <div className="flex items-center justify-center space-x-8 text-sm text-slate-400">
              <div className="flex items-center space-x-2">
                <div className="w-2 h-2 bg-emerald-500 rounded-full animate-pulse"></div>
                <span>Early access open</span>
              </div>
              <div className="flex items-center space-x-2">
                <span>🇦🇺</span>
                <span>Built for Australia</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Problem Section */}
      <section className="py-20 px-4">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              The reference game is broken
            </h2>
            <p className="text-xl text-slate-300">
              Every tradie knows these pain points
            </p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                emoji: "⏰",
                quote: "Every new customer wants references. Hour finding old clients willing to take a call."
              },
              {
                emoji: "🤥",
                quote: "Dodgy tiler has 200 five-star Google reviews. Half are fake."
              },
              {
                emoji: "🤷‍♀️",
                quote: "Homeowners can't verify if references are real. Just trust Google and hope."
              }
            ].map((problem, index) => (
              <div key={index} className="group">
                <div className="p-8 bg-slate-900/50 border border-slate-800 rounded-2xl backdrop-blur-sm hover:border-slate-700 transition-all transform hover:scale-105">
                  <div className="text-4xl mb-4">{problem.emoji}</div>
                  <blockquote className="text-lg text-slate-300 italic leading-relaxed">
                    "{problem.quote}"
                  </blockquote>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Show Don't Tell Section */}
      <section className="py-20 px-4 bg-slate-900/30">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              See the difference
            </h2>
            <p className="text-xl text-slate-300">
              Generic Google reviews vs verified TradeRef profiles
            </p>
          </div>
          
          <div className="grid lg:grid-cols-2 gap-12 items-start">
            {/* Before - Google Reviews */}
            <div className="space-y-4">
              <div className="flex items-center space-x-2 mb-6">
                <span className="text-red-400 text-2xl">❌</span>
                <h3 className="text-2xl font-bold text-red-400">Before: Google Reviews</h3>
              </div>
              
              <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-6 backdrop-blur-sm">
                <div className="flex items-center space-x-3 mb-4">
                  <div className="w-10 h-10 bg-blue-500 rounded-full flex items-center justify-center text-white font-bold">
                    DT
                  </div>
                  <div>
                    <h4 className="font-semibold">Dave's Tiling</h4>
                    <div className="flex items-center space-x-2">
                      <div className="flex text-yellow-400">★★★★★</div>
                      <span className="text-slate-400">4.8 (200 reviews)</span>
                    </div>
                  </div>
                </div>
                
                <div className="space-y-3">
                  {[
                    { name: "John S", review: "Great job!", date: "1 week ago" },
                    { name: "Sarah M", review: "Professional", date: "1 week ago" },
                    { name: "Mike R", review: "Recommend", date: "1 week ago" },
                    { name: "Lisa K", review: "Good work", date: "1 week ago" }
                  ].map((review, index) => (
                    <div key={index} className="border-l-2 border-slate-600 pl-4">
                      <div className="flex items-center space-x-2 mb-1">
                        <span className="font-medium text-sm">{review.name}</span>
                        <div className="flex text-yellow-400 text-xs">★★★★★</div>
                      </div>
                      <p className="text-slate-300 text-sm">{review.review}</p>
                      <p className="text-slate-500 text-xs">{review.date}</p>
                    </div>
                  ))}
                </div>
                
                <div className="mt-4 p-3 bg-red-500/10 border border-red-500/20 rounded-lg">
                  <p className="text-red-400 text-sm">🚨 Suspicious: All generic reviews posted same week</p>
                </div>
              </div>
            </div>

            {/* After - TradeRef */}
            <div className="space-y-4">
              <div className="flex items-center space-x-2 mb-6">
                <span className="text-emerald-400 text-2xl">✅</span>
                <h3 className="text-2xl font-bold text-emerald-400">After: TradeRef Profile</h3>
              </div>
              
              <div className="bg-gradient-to-br from-emerald-500/10 to-slate-800/50 border border-emerald-500/20 rounded-xl p-6 backdrop-blur-sm">
                <div className="flex items-center space-x-3 mb-4">
                  <div className="w-10 h-10 bg-emerald-500 rounded-full flex items-center justify-center text-white font-bold">
                    DT
                  </div>
                  <div>
                    <div className="flex items-center space-x-2">
                      <h4 className="font-semibold">Dave's Tiling</h4>
                      <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
                        ✓ Verified
                      </span>
                    </div>
                    <p className="text-slate-400 text-sm">3 verified references</p>
                  </div>
                </div>
                
                <div className="space-y-4">
                  <div className="border border-emerald-500/20 rounded-lg p-4 bg-emerald-500/5">
                    <div className="flex items-start justify-between mb-2">
                      <div>
                        <div className="flex items-center space-x-2">
                          <span className="font-medium text-sm">Sarah Chen</span>
                          <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-emerald-500/20 text-emerald-400">
                            ✓ Verified Client
                          </span>
                        </div>
                        <p className="text-slate-400 text-xs">Paddington, NSW</p>
                      </div>
                      <span className="text-slate-500 text-xs">2 months ago</span>
                    </div>
                    
                    <div className="mb-3">
                      <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-slate-700 text-slate-300">
                        🏠 Bathroom renovation
                      </span>
                    </div>
                    
                    <p className="text-slate-300 text-sm leading-relaxed">
                      "Dave replaced entire bathroom in 3 weeks. Waterproofing passed first go. Small delay on vanity but kept us informed. Would use again."
                    </p>
                    
                    <div className="flex items-center space-x-4 mt-3 text-xs text-slate-400">
                      <span>📱 Verified via SMS</span>
                      <span>📅 Project completed Aug 2024</span>
                    </div>
                  </div>
                </div>
                
                <div className="mt-4 p-3 bg-emerald-500/10 border border-emerald-500/20 rounded-lg">
                  <p className="text-emerald-400 text-sm">✨ Real client, real project, real feedback</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-20 px-4">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              How it works
            </h2>
            <p className="text-xl text-slate-300">
              Three simple steps to verified references
            </p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                step: "1",
                icon: "📱",
                title: "Send reference request",
                description: "Text your client a quick reference request. Takes 30 seconds."
              },
              {
                step: "2",
                icon: "✅",
                title: "Client verifies instantly",
                description: "They confirm the job details with a simple reply. No phone calls."
              },
              {
                step: "3",
                icon: "🔗",
                title: "Share verified profile",
                description: "Send prospects your TradeRef link. Instant trust, more jobs."
              }
            ].map((step, index) => (
              <div key={index} className="text-center group">
                <div className="relative mb-6">
                  <div className="w-20 h-20 mx-auto bg-gradient-to-br from-emerald-500 to-emerald-600 rounded-2xl flex items-center justify-center text-3xl transform group-hover:scale-110 transition-transform">
                    {step.icon}
                  </div>
                  <div className="absolute -top-2 -right-2 w-8 h-8 bg-slate-800 border-2 border-emerald-500 rounded-full flex items-center justify-center text-sm font-bold text-emerald-400">
                    {step.step}
                  </div>
                </div>
                <h3 className="text-xl font-semibold mb-3">{step.title}</h3>
                <p className="text-slate-300 leading-relaxed">{step.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-20 px-4 bg-slate-900/30">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              Everything you need
            </h2>
            <p className="text-xl text-slate-300">
              Built for Australian tradies
            </p>
          </div>
          
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            {[
              {
                icon: "📱",
                title: "SMS Verification",
                description: "Clients verify via text message. No apps, no hassle."
              },
              {
                icon: "✅",
                title: "Verified Badges",
                description: "Clear verification status. Prospects know it's legit."
              },
              {
                icon: "🔗",
                title: "Shareable Links",
                description: "One link to share everywhere. Social media, quotes, business cards."
              },
              {
                icon: "💬",
                title: "Review Responses",
                description: "Reply to feedback professionally. Show you care about quality."
              },
              {
                icon: "📸",
                title: "Portfolio Builder",
                description: "Add photos to references. Show your best work alongside reviews."
              },
              {
                icon: "🇦🇺",
                title: "Australian Built",
                description: "Made for Aussie tradies. Understands local business needs."
              }
            ].map((feature, index) => (
              <div key={index} className="group">
                <div className="p-6 bg-slate-800/50 border border-slate-700 rounded-xl backdrop-blur-sm hover:border-emerald-500/30 hover:bg-emerald-500/5 transition-all">
                  <div className="text-3xl mb-4">{feature.icon}</div>
                  <h3 className="text-lg font-semibold mb-2">{feature.title}</h3>
                  <p className="text-slate-300 text-sm leading-relaxed">{feature.description}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="py-20 px-4">
        <div className="max-w-4xl mx-auto text-center">
          <div className="space-y-8">
            <div>
              <h2 className="text-3xl sm:text-4xl font-bold mb-4">
                Trusted by Australian construction
              </h2>
              <p className="text-xl text-slate-300">
                Built by tradies, for tradies
              </p>
            </div>
            
            <div className="grid md:grid-cols-3 gap-8">
              <div className="p-6 bg-slate-800/30 border border-slate-700 rounded-xl backdrop-blur-sm">
                <div className="text-2xl mb-2">🏗️</div>
                <h3 className="font-semibold mb-2">Industry Focused</h3>
                <p className="text-slate-300 text-sm">Purpose-built for Australian construction and trade industries</p>
              </div>
              <div className="p-6 bg-slate-800/30 border border-slate-700 rounded-xl backdrop-blur-sm">
                <div className="text-2xl mb-2">🛡️</div>
                <h3 className="font-semibold mb-2">Privacy First</h3>
                <p className="text-slate-300 text-sm">Client details protected. Only verified info shared publicly</p>
              </div>
              <div className="p-6 bg-slate-800/30 border border-slate-700 rounded-xl backdrop-blur-sm">
                <div className="text-2xl mb-2">⚡</div>
                <h3 className="font-semibold mb-2">Lightning Fast</h3>
                <p className="text-slate-300 text-sm">References verified in minutes, not days</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-20 px-4 bg-slate-900/30">
        <div className="max-w-4xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              Common questions
            </h2>
            <p className="text-xl text-slate-300">
              Everything you need to know
            </p>
          </div>
          
          <div className="space-y-4">
            {[
              {
                question: "How do clients verify their reviews?",
                answer: "We send them a simple SMS with job details. They reply to confirm it's accurate. Takes 30 seconds, no apps required."
              },
              {
                question: "What if a client doesn't respond?",
                answer: "No worries. We send gentle reminders and you can always try a different client. Only verified references appear on your profile."
              },
              {
                question: "Can I add photos to my references?",
                answer: "Absolutely. Upload before/after shots, progress pics, or finished work. Visual proof alongside verified reviews is powerful."
              },
              {
                question: "How much does TradeRef cost?",
                answer: "We're still in private beta working out pricing with early users. Join the waitlist to get special early access rates."
              },
              {
                question: "Is this just for big construction companies?",
                answer: "Not at all. Built for solo tradies, small crews, and growing businesses. If you do quality work, TradeRef helps you prove it."
              }
            ].map((faq, index) => (
              <div key={index} className="border border-slate-700 rounded-xl overflow-hidden backdrop-blur-sm">
                <button
                  onClick={() => setExpandedFaq(expandedFaq === index ? null : index)}
                  className="w-full p-6 text-left hover:bg-slate-800/30 transition-colors focus:outline-none focus:bg-slate-800/30"
                >
                  <div className="flex items-center justify-between">
                    <h3 className="font-semibold text-lg pr-4">{faq.question}</h3>
                    <div className={`transform transition-transform ${expandedFaq === index ? 'rotate-180' : ''}`}>
                      <svg className="w-5 h-5 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                      </svg>
                    </div>
                  </div>
                </button>
                {expandedFaq === index && (
                  <div className="px-6 pb-6">
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
          <div className="space-y-8">
            <div>
              <h2 className="text-3xl sm:text-4xl font-bold mb-4">
                Ready to build real trust?
              </h2>
              <p className="text-xl text-slate-300 mb-2">
                Join 1,200+ tradies getting early access
              </p>
              <p className="text-slate-400">
                Limited spots available. Invitation only.
              </p>
            </div>
            
            <WaitlistForm showUrgency={true} />
            
            <div className="flex items-center justify-center space-x-6 text-sm text-slate-400">
              <span>✅ No spam</span>
              <span>✅ Early access pricing</span>
              <span>✅ Cancel anytime</span>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-slate-800 py-12 px-4">
        <div className="max-w-6xl mx-auto">
          <div className="flex flex-col md:flex-row items-center justify-between space-y-4 md:space-y-0">
            <div className="flex items-center space-x-3">
              <div className="w-8 h-8 bg-gradient-to-br from-emerald-500 to-emerald-600 rounded-lg flex items-center justify-center">
                <span className="text-white font-bold text-sm">TR</span>
              </div>
              <span className="font-semibold">TradeRef</span>
            </div>
            
            <div className="text-slate-400 text-sm">
              Built by{' '}
              <a 
                href="https://levasolutions.com.au" 
                target="_blank" 
                rel="noopener noreferrer"
                className="text-emerald-400 hover:text-emerald-300 transition-colors"
              >
                Leva Solutions
              </a>
            </div>
          </div>
        </div>
      </footer>

      <Analytics />
    </div>
  )
}