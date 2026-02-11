'use client'

import { useState } from 'react'
import { Geist } from 'next/font/google'
import { Analytics } from '@vercel/analytics/react'

const geist = Geist({ subsets: ['latin'] })

export default function Page() {
  const [email, setEmail] = useState('')
  const [finalEmail, setFinalEmail] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [isFinalSubmitting, setIsFinalSubmitting] = useState(false)
  const [openFaq, setOpenFaq] = useState<number | null>(null)

  // Waitlist API endpoint - deployed Google Apps Script web app
  const WAITLIST_API_URL = "/api/waitlist";

  const handleSubmit = async (e: React.FormEvent, isFinal = false) => {
    e.preventDefault()
    const currentEmail = isFinal ? finalEmail : email
    const setSubmitting = isFinal ? setIsFinalSubmitting : setIsSubmitting

    if (!currentEmail) return

    setSubmitting(true)

    try {
      // Get UTM params from URL
      const urlParams = new URLSearchParams(window.location.search);

      await fetch(WAITLIST_API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: currentEmail,
          product: 'claimstack',
          referrer: document.referrer || '',
          utmSource: urlParams.get('utm_source') || '',
          utmMedium: urlParams.get('utm_medium') || '',
          utmCampaign: urlParams.get('utm_campaign') || ''
        })
      })

      if (isFinal) {
        setFinalEmail('')
      } else {
        setEmail('')
      }

      alert('Thanks! You\'re on the waitlist. We\'ll be in touch soon.')
    } catch (error) {
      alert('Something went wrong. Please try again.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className={`${geist.className} min-h-screen bg-slate-950 text-white`}>
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-blue-500/10 via-transparent to-purple-500/10"></div>
        <div className="relative max-w-6xl mx-auto px-4 py-16 sm:py-24">
          <div className="text-center space-y-8">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-blue-500/10 border border-blue-500/20 backdrop-blur-sm">
              <span className="w-2 h-2 bg-blue-500 rounded-full animate-pulse"></span>
              <span className="text-sm text-blue-300">Invitation Only • Early Access</span>
            </div>
            
            <h1 className="text-4xl sm:text-6xl lg:text-7xl font-bold tracking-tight">
              Get paid on time,{' '}
              <span className="bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">
                every time
              </span>
            </h1>
            
            <p className="text-xl sm:text-2xl text-slate-300 max-w-3xl mx-auto leading-relaxed">
              Stop chasing payments. ClaimStack automates your progress claims, tracks variations, and keeps your cash flow healthy.
            </p>
            
            <form onSubmit={(e) => handleSubmit(e)} className="max-w-md mx-auto">
              <div className="flex gap-3">
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="your@email.com.au"
                  className="flex-1 px-4 py-3 rounded-lg bg-slate-800/50 border border-slate-700 backdrop-blur-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                  required
                />
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="px-6 py-3 bg-gradient-to-r from-blue-500 to-blue-600 rounded-lg font-semibold hover:from-blue-600 hover:to-blue-700 transition-all transform hover:scale-105 disabled:opacity-50 disabled:transform-none"
                >
                  {isSubmitting ? '...' : 'Join Waitlist'}
                </button>
              </div>
            </form>
            
            <div className="flex items-center justify-center gap-6 text-sm text-slate-400">
              <div className="flex items-center gap-2">
                <div className="flex -space-x-2">
                  <div className="w-8 h-8 bg-gradient-to-br from-blue-400 to-purple-400 rounded-full border-2 border-slate-950"></div>
                  <div className="w-8 h-8 bg-gradient-to-br from-green-400 to-blue-400 rounded-full border-2 border-slate-950"></div>
                  <div className="w-8 h-8 bg-gradient-to-br from-purple-400 to-pink-400 rounded-full border-2 border-slate-950"></div>
                </div>
                <span>Early access open</span>
              </div>
              <div className="w-1 h-1 bg-slate-600 rounded-full"></div>
              <span>🇦🇺 Built for Australian construction</span>
            </div>
          </div>
        </div>
      </section>

      {/* Problem Section */}
      <section className="py-16 sm:py-24">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Sound familiar?</h2>
            <p className="text-xl text-slate-400">Every subbie knows these pain points</p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                emoji: "😤",
                quote: "Finished work 3 weeks ago. Still chasing the builder for payment."
              },
              {
                emoji: "🤦‍♂️",
                quote: "Claim bounced — missed a variation. Another 30 days wait. Suppliers want paying."
              },
              {
                emoji: "📉",
                quote: "Doing $80K months but bank says $12K. Everyone pays 60-90 days late."
              }
            ].map((problem, index) => (
              <div key={index} className="group">
                <div className="p-8 rounded-2xl bg-slate-900/50 border border-slate-800 backdrop-blur-sm hover:border-slate-700 transition-all duration-300 group-hover:transform group-hover:scale-105">
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
      <section className="py-16 sm:py-24 bg-slate-900/30">
        <div className="max-w-7xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">From chaos to control</h2>
            <p className="text-xl text-slate-400">See the difference ClaimStack makes</p>
          </div>
          
          <div className="grid lg:grid-cols-2 gap-12 items-center">
            {/* Before */}
            <div className="space-y-6">
              <div className="flex items-center gap-3 mb-6">
                <div className="px-3 py-1 bg-red-500/20 text-red-300 rounded-full text-sm font-medium">Before</div>
                <h3 className="text-2xl font-bold text-slate-300">Manual tracking nightmare</h3>
              </div>
              
              <div className="p-6 rounded-2xl bg-slate-800/50 border border-slate-700 backdrop-blur-sm">
                <div className="space-y-4">
                  <div className="flex items-center justify-between p-3 bg-red-900/20 rounded-lg border border-red-800/30">
                    <span className="text-sm">📋 Handwritten notes</span>
                    <span className="text-red-400 text-xs">MESSY</span>
                  </div>
                  <div className="flex items-center justify-between p-3 bg-red-900/20 rounded-lg border border-red-800/30">
                    <span className="text-sm">🧮 Calculator & Excel</span>
                    <span className="text-red-400 text-xs">ERROR-PRONE</span>
                  </div>
                  <div className="flex items-center justify-between p-3 bg-red-900/20 rounded-lg border border-red-800/30">
                    <span className="text-sm">📞 Chasing payments</span>
                    <span className="text-red-400 text-xs">TIME WASTING</span>
                  </div>
                  <div className="p-4 bg-red-900/30 rounded-lg border border-red-700/50">
                    <div className="text-xs text-red-300 mb-2">Sticky note:</div>
                    <div className="text-sm font-mono text-red-200">"CHASE DAVE - 3 weeks overdue 😡"</div>
                  </div>
                </div>
              </div>
            </div>

            {/* After */}
            <div className="space-y-6">
              <div className="flex items-center gap-3 mb-6">
                <div className="px-3 py-1 bg-green-500/20 text-green-300 rounded-full text-sm font-medium">After</div>
                <h3 className="text-2xl font-bold text-slate-300">ClaimStack dashboard</h3>
              </div>
              
              <div className="p-6 rounded-2xl bg-slate-800/50 border border-slate-700 backdrop-blur-sm">
                <div className="space-y-4">
                  <div className="flex items-center justify-between p-3 bg-blue-900/20 rounded-lg border border-blue-700/30">
                    <span className="text-sm">🏗️ Barrett Constructions</span>
                    <div className="flex items-center gap-2">
                      <div className="w-16 h-2 bg-slate-700 rounded-full overflow-hidden">
                        <div className="w-3/4 h-full bg-blue-500 rounded-full"></div>
                      </div>
                      <span className="text-blue-400 text-xs">75%</span>
                    </div>
                  </div>
                  <div className="flex items-center justify-between p-3 bg-blue-900/20 rounded-lg border border-blue-700/30">
                    <span className="text-sm">🏠 Riverside Apartments</span>
                    <div className="flex items-center gap-2">
                      <div className="w-16 h-2 bg-slate-700 rounded-full overflow-hidden">
                        <div className="w-1/2 h-full bg-blue-500 rounded-full"></div>
                      </div>
                      <span className="text-blue-400 text-xs">50%</span>
                    </div>
                  </div>
                  <div className="flex items-center justify-between p-3 bg-blue-900/20 rounded-lg border border-blue-700/30">
                    <span className="text-sm">🏢 Commercial Fitout</span>
                    <div className="flex items-center gap-2">
                      <div className="w-16 h-2 bg-slate-700 rounded-full overflow-hidden">
                        <div className="w-1/4 h-full bg-blue-500 rounded-full"></div>
                      </div>
                      <span className="text-blue-400 text-xs">25%</span>
                    </div>
                  </div>
                  <div className="p-4 bg-green-900/30 rounded-lg border border-green-700/50">
                    <div className="flex items-center gap-2 mb-2">
                      <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
                      <div className="text-xs text-green-300">Payment received</div>
                    </div>
                    <div className="text-lg font-semibold text-green-200">$8,400 from Barrett Constructions</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-16 sm:py-24">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">How it works</h2>
            <p className="text-xl text-slate-400">Three simple steps to better cash flow</p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                number: "1",
                title: "Set up contract",
                description: "Upload your contract. We extract key dates, milestones, and payment terms automatically.",
                icon: "📋"
              },
              {
                number: "2",
                title: "Submit compliant claims",
                description: "Generate progress claims that meet contract requirements. Never miss a variation again.",
                icon: "📊"
              },
              {
                number: "3",
                title: "Track & forecast",
                description: "Monitor payments, chase overdue amounts, and forecast your cash flow with confidence.",
                icon: "💰"
              }
            ].map((step, index) => (
              <div key={index} className="relative group">
                <div className="p-8 rounded-2xl bg-slate-900/50 border border-slate-800 backdrop-blur-sm hover:border-blue-500/50 transition-all duration-300 group-hover:transform group-hover:scale-105">
                  <div className="flex items-center gap-4 mb-6">
                    <div className="w-12 h-12 bg-gradient-to-br from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-white font-bold text-lg">
                      {step.number}
                    </div>
                    <div className="text-3xl">{step.icon}</div>
                  </div>
                  <h3 className="text-xl font-bold mb-3">{step.title}</h3>
                  <p className="text-slate-400 leading-relaxed">{step.description}</p>
                </div>
                {index < 2 && (
                  <div className="hidden md:block absolute top-1/2 -right-4 w-8 h-0.5 bg-gradient-to-r from-blue-500 to-transparent transform -translate-y-1/2"></div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-16 sm:py-24 bg-slate-900/30">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Everything you need</h2>
            <p className="text-xl text-slate-400">Built specifically for Australian subcontractors</p>
          </div>
          
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            {[
              {
                icon: "🏗️",
                title: "Claim Builder",
                description: "Generate compliant progress claims in minutes, not hours."
              },
              {
                icon: "📝",
                title: "Variation Tracker",
                description: "Never miss a variation. Track changes and get paid for extra work."
              },
              {
                icon: "📅",
                title: "Payment Calendar",
                description: "See when payments are due and track what's overdue."
              },
              {
                icon: "🛡️",
                title: "Rejection Shield",
                description: "Avoid claim rejections with built-in compliance checks."
              },
              {
                icon: "📈",
                title: "Cash Flow Forecast",
                description: "Predict your cash position and plan ahead with confidence."
              },
              {
                icon: "🔗",
                title: "Xero Integration",
                description: "Sync seamlessly with your existing accounting setup."
              }
            ].map((feature, index) => (
              <div key={index} className="group">
                <div className="p-6 rounded-2xl bg-slate-800/50 border border-slate-700 backdrop-blur-sm hover:border-blue-500/50 transition-all duration-300 group-hover:transform group-hover:scale-105">
                  <div className="text-3xl mb-4">{feature.icon}</div>
                  <h3 className="text-lg font-bold mb-2">{feature.title}</h3>
                  <p className="text-slate-400 text-sm leading-relaxed">{feature.description}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="py-16 sm:py-24">
        <div className="max-w-4xl mx-auto px-4 text-center">
          <div className="space-y-8">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-green-500/10 border border-green-500/20 backdrop-blur-sm">
              <span className="text-green-400">🇦🇺</span>
              <span className="text-sm text-green-300">Built for Australian Construction Industry</span>
            </div>
            
            <h2 className="text-3xl sm:text-4xl font-bold">Trusted by tradies across Australia</h2>
            
            <div className="grid md:grid-cols-3 gap-8 mt-12">
              <div className="p-6 rounded-2xl bg-slate-900/50 border border-slate-800 backdrop-blur-sm">
                <div className="text-2xl font-bold text-blue-400 mb-2">AS 2124</div>
                <div className="text-sm text-slate-400">Compliant with Australian construction contracts</div>
              </div>
              <div className="p-6 rounded-2xl bg-slate-900/50 border border-slate-800 backdrop-blur-sm">
                <div className="text-2xl font-bold text-blue-400 mb-2">Security Act</div>
                <div className="text-sm text-slate-400">Meets Building Industry Payment Security requirements</div>
              </div>
              <div className="p-6 rounded-2xl bg-slate-900/50 border border-slate-800 backdrop-blur-sm">
                <div className="text-2xl font-bold text-blue-400 mb-2">Local Support</div>
                <div className="text-sm text-slate-400">Australian-based team who understand your challenges</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-16 sm:py-24 bg-slate-900/30">
        <div className="max-w-4xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Common questions</h2>
            <p className="text-xl text-slate-400">Everything you need to know</p>
          </div>
          
          <div className="space-y-4">
            {[
              {
                question: "How does ClaimStack help me get paid faster?",
                answer: "ClaimStack ensures your progress claims are compliant and submitted on time. We track payment due dates, send automated reminders, and help you chase overdue payments professionally. Most users see a 40% reduction in payment delays."
              },
              {
                question: "Does it work with my existing contracts?",
                answer: "Yes! ClaimStack works with standard Australian construction contracts including AS 2124, AS 4000, and most custom contracts. We extract the key payment terms and milestones automatically."
              },
              {
                question: "What about variations and extras?",
                answer: "Our Variation Tracker ensures you never miss claiming for extra work. We help you document variations properly and include them in your progress claims with the right supporting evidence."
              },
              {
                question: "How much does it cost?",
                answer: "We're still finalising pricing, but it'll be affordable for subcontractors of all sizes. Join the waitlist to get early access pricing and be the first to know when we launch."
              },
              {
                question: "When will ClaimStack be available?",
                answer: "We're launching in early 2024. Waitlist members get first access and special launch pricing. We'll keep you updated on our progress and give you early access to test the platform."
              }
            ].map((faq, index) => (
              <div key={index} className="border border-slate-800 rounded-2xl bg-slate-900/50 backdrop-blur-sm overflow-hidden">
                <button
                  onClick={() => setOpenFaq(openFaq === index ? null : index)}
                  className="w-full p-6 text-left hover:bg-slate-800/50 transition-colors flex items-center justify-between"
                >
                  <span className="font-semibold text-lg">{faq.question}</span>
                  <span className={`text-2xl transition-transform ${openFaq === index ? 'rotate-45' : ''}`}>+</span>
                </button>
                {openFaq === index && (
                  <div className="px-6 pb-6">
                    <p className="text-slate-400 leading-relaxed">{faq.answer}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="py-16 sm:py-24">
        <div className="max-w-4xl mx-auto px-4 text-center">
          <div className="space-y-8">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-red-500/10 border border-red-500/20 backdrop-blur-sm">
              <span className="w-2 h-2 bg-red-500 rounded-full animate-pulse"></span>
              <span className="text-sm text-red-300">Limited Early Access • Launching Soon</span>
            </div>
            
            <h2 className="text-3xl sm:text-5xl font-bold">
              Stop chasing payments.{' '}
              <span className="bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">
                Start getting paid.
              </span>
            </h2>
            
            <p className="text-xl text-slate-400 max-w-2xl mx-auto">
              Request early access. Limited spots available.
            </p>
            
            <form onSubmit={(e) => handleSubmit(e, true)} className="max-w-md mx-auto">
              <div className="flex gap-3">
                <input
                  type="email"
                  value={finalEmail}
                  onChange={(e) => setFinalEmail(e.target.value)}
                  placeholder="your@email.com.au"
                  className="flex-1 px-4 py-3 rounded-lg bg-slate-800/50 border border-slate-700 backdrop-blur-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                  required
                />
                <button
                  type="submit"
                  disabled={isFinalSubmitting}
                  className="px-6 py-3 bg-gradient-to-r from-blue-500 to-blue-600 rounded-lg font-semibold hover:from-blue-600 hover:to-blue-700 transition-all transform hover:scale-105 disabled:opacity-50 disabled:transform-none"
                >
                  {isFinalSubmitting ? '...' : 'Get Early Access'}
                </button>
              </div>
            </form>
            
            <p className="text-sm text-slate-500">
              No spam. Unsubscribe anytime. We respect your inbox.
            </p>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-slate-800 py-8">
        <div className="max-w-6xl mx-auto px-4 text-center">
          <p className="text-slate-500">
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