'use client'

import { useState } from 'react'
import { Geist } from 'next/font/google'
import { Analytics } from '@vercel/analytics/react'

const geist = Geist({ subsets: ['latin'] })

export default function Page() {
  const [email, setEmail] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [submitMessage, setSubmitMessage] = useState('')
  const [openFaq, setOpenFaq] = useState<number | null>(null)

  const calendlyUrl = process.env.NEXT_PUBLIC_CALENDLY_URL || 'https://calendly.com/'

  // Waitlist API endpoint
  const WAITLIST_API_URL = '/api/waitlist'

  const handleSubmit = async (e: React.FormEvent, source: string) => {
    e.preventDefault()
    if (!email) return

    setIsSubmitting(true)
    try {
      // Get UTM params from URL
      const urlParams = new URLSearchParams(window.location.search)

      const response = await fetch(WAITLIST_API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email,
          product: 'quotefollow',
          referrer: source || document.referrer || '',
          utmSource: urlParams.get('utm_source') || '',
          utmMedium: urlParams.get('utm_medium') || '',
          utmCampaign: urlParams.get('utm_campaign') || '',
        }),
      })

      if (response.ok) {
        setSubmitMessage("Thanks! You're on the list. We'll be in touch soon.")
        setEmail('')
      } else {
        setSubmitMessage('Something went wrong. Please try again.')
      }
    } catch (error) {
      setSubmitMessage('Something went wrong. Please try again.')
    }
    setIsSubmitting(false)
  }

  const toggleFaq = (index: number) => {
    setOpenFaq(openFaq === index ? null : index)
  }

  return (
    <div className={`${geist.className} min-h-screen bg-slate-950 text-white`}>
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-blue-500/10 via-transparent to-purple-500/10"></div>
        <div className="relative max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 pt-16 pb-24">
          <div className="text-center">
            <div className="inline-flex items-center px-4 py-2 rounded-full bg-blue-500/10 border border-blue-500/20 backdrop-blur-sm mb-8">
              <span className="text-blue-400 text-sm font-medium">🚀 Invitation Only</span>
            </div>

            <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold mb-6 bg-gradient-to-r from-white via-slate-200 to-slate-400 bg-clip-text text-transparent">
              Stop losing jobs to silence
            </h1>

            <p className="text-xl sm:text-2xl text-slate-300 mb-8 max-w-3xl mx-auto leading-relaxed">
              QuoteFollow automatically follows up on your quotes so you never lose another job to poor communication.
            </p>

            {/* Above-the-fold paid pilot CTA */}
            <div className="max-w-2xl mx-auto mb-8">
              <a
                href={calendlyUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center justify-center px-6 py-3 bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700 rounded-lg font-medium transition-all transform hover:scale-105"
              >
                Book a 15-min call
              </a>
              <p className="mt-3 text-sm sm:text-base text-slate-300">
                Founding member pilot: $500 deposit + $299/mo for 6 months (first 20)
              </p>
            </div>

            <form onSubmit={(e) => handleSubmit(e, 'hero')} className="max-w-md mx-auto mb-8">
              <div className="flex flex-col sm:flex-row gap-3">
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="Enter your email"
                  className="flex-1 px-4 py-3 rounded-lg bg-slate-800/50 border border-slate-700 backdrop-blur-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                  required
                />
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="px-6 py-3 bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700 rounded-lg font-medium transition-all transform hover:scale-105 disabled:opacity-50 disabled:transform-none"
                >
                  {isSubmitting ? 'Joining...' : 'Request Early Access'}
                </button>
              </div>
              {submitMessage && (
                <p className={`mt-3 text-sm ${submitMessage.includes('Thanks') ? 'text-green-400' : 'text-red-400'}`}>
                  {submitMessage}
                </p>
              )}
            </form>

            <div className="flex items-center justify-center gap-2 text-slate-400">
              <div className="flex -space-x-2">
                <div className="w-8 h-8 rounded-full bg-gradient-to-r from-blue-500 to-purple-500"></div>
                <div className="w-8 h-8 rounded-full bg-gradient-to-r from-green-500 to-blue-500"></div>
                <div className="w-8 h-8 rounded-full bg-gradient-to-r from-purple-500 to-pink-500"></div>
              </div>
              <span className="text-sm">Request early access</span>
            </div>

            {/* Instant proof block */}
            <div className="mt-12 max-w-4xl mx-auto">
              <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 sm:p-8 text-left">
                <div className="flex items-center justify-between gap-4 mb-6">
                  <h3 className="text-lg sm:text-xl font-semibold">Instant proof</h3>
                  <span className="text-xs sm:text-sm text-slate-400">What happens after you send a quote</span>
                </div>

                <div className="flex flex-col md:flex-row md:items-stretch gap-4">
                  <div className="flex-1 bg-slate-900/40 border border-slate-700/50 rounded-lg p-4">
                    <div className="text-xs text-slate-400 mb-2">Step 1</div>
                    <div className="font-medium">Quote sent</div>
                    <div className="mt-2 text-sm text-slate-300">"Bathroom reno — $8,500"</div>
                  </div>

                  <div className="hidden md:flex items-center text-slate-600">→</div>

                  <div className="flex-1 bg-blue-900/20 border border-blue-500/20 rounded-lg p-4">
                    <div className="text-xs text-blue-300/80 mb-2">Step 2</div>
                    <div className="font-medium text-blue-200">Auto SMS + email follow-up</div>
                    <div className="mt-2 text-sm text-slate-300">"Just checking you received the quote"</div>
                  </div>

                  <div className="hidden md:flex items-center text-slate-600">→</div>

                  <div className="flex-1 bg-slate-900/40 border border-slate-700/50 rounded-lg p-4">
                    <div className="text-xs text-slate-400 mb-2">Step 3</div>
                    <div className="font-medium">Customer replies</div>
                    <div className="mt-2 text-sm text-slate-300">"Yep — can you start next week?"</div>
                  </div>

                  <div className="hidden md:flex items-center text-slate-600">→</div>

                  <div className="flex-1 bg-green-900/20 border border-green-500/20 rounded-lg p-4">
                    <div className="text-xs text-green-300/80 mb-2">Step 4</div>
                    <div className="font-medium text-green-200">Hot quote alert</div>
                    <div className="mt-2 text-sm text-slate-300">You're notified instantly to close the job.</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Problem Section */}
      <section className="py-24 bg-slate-900/50">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Sound familiar?</h2>
            <p className="text-xl text-slate-300">These are the stories we hear every day</p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-4xl mb-4">😤</div>
              <blockquote className="text-slate-300 italic mb-4">"Sent 15 quotes last month. Followed up on 3. The other 12? Who knows."</blockquote>
              <div className="text-sm text-slate-400">— Plumber, Sydney</div>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-4xl mb-4">💸</div>
              <blockquote className="text-slate-300 italic mb-4">
                "Customer went with someone else because I took 4 days to follow up."
              </blockquote>
              <div className="text-sm text-slate-400">— Electrician, Melbourne</div>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-4xl mb-4">⏰</div>
              <blockquote className="text-slate-300 italic mb-4">
                "Should follow up but on the tools at 6am. By the time I remember, it's been two weeks."
              </blockquote>
              <div className="text-sm text-slate-400">— Builder, Brisbane</div>
            </div>
          </div>
        </div>
      </section>

      {/* Show Don't Tell Section */}
      <section className="py-24">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Here's what changes</h2>
            <p className="text-xl text-slate-300">Same quote. Different outcome.</p>
          </div>

          <div className="space-y-12">
            {/* Without QuoteFollow */}
            <div className="bg-red-500/5 border border-red-500/20 rounded-xl p-8">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 rounded-full bg-red-500 flex items-center justify-center">
                  <span className="text-white text-lg">✕</span>
                </div>
                <h3 className="text-xl font-semibold text-red-400">Without QuoteFollow</h3>
              </div>

              <div className="flex flex-col sm:flex-row items-start sm:items-center gap-4 overflow-x-auto">
                <div className="flex-shrink-0 bg-slate-800 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-slate-400 mb-1">Monday</div>
                  <div className="text-white">Quote sent to Sarah</div>
                  <div className="text-xs text-slate-500 mt-1">Bathroom renovation - $8,500</div>
                </div>

                <div className="hidden sm:block text-slate-600">→</div>

                <div className="flex-shrink-0 bg-slate-800 rounded-lg p-4 min-w-[200px] opacity-50">
                  <div className="text-sm text-slate-400 mb-1">Tuesday - Wednesday</div>
                  <div className="text-slate-400">Silence...</div>
                  <div className="text-xs text-slate-500 mt-1">Too busy to follow up</div>
                </div>

                <div className="hidden sm:block text-slate-600">→</div>

                <div className="flex-shrink-0 bg-red-900/30 border border-red-500/30 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-red-400 mb-1">Thursday</div>
                  <div className="text-red-300">Sarah books competitor</div>
                  <div className="text-xs text-red-500 mt-1">They followed up Wednesday</div>
                </div>

                <div className="hidden sm:block text-slate-600">→</div>

                <div className="flex-shrink-0 bg-slate-800 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-slate-400 mb-1">Friday</div>
                  <div className="text-slate-300">You finally call</div>
                  <div className="text-xs text-slate-500 mt-1">"Oh, we went with someone else"</div>
                </div>
              </div>
            </div>

            {/* With QuoteFollow */}
            <div className="bg-green-500/5 border border-green-500/20 rounded-xl p-8">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 rounded-full bg-green-500 flex items-center justify-center">
                  <span className="text-white text-lg">✓</span>
                </div>
                <h3 className="text-xl font-semibold text-green-400">With QuoteFollow</h3>
              </div>

              <div className="flex flex-col sm:flex-row items-start sm:items-center gap-4 overflow-x-auto">
                <div className="flex-shrink-0 bg-slate-800 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-slate-400 mb-1">Monday</div>
                  <div className="text-white">Quote sent to Sarah</div>
                  <div className="text-xs text-slate-500 mt-1">Bathroom renovation - $8,500</div>
                </div>

                <div className="hidden sm:block text-slate-600">→</div>

                <div className="flex-shrink-0 bg-blue-900/30 border border-blue-500/30 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-blue-400 mb-1">Wednesday</div>
                  <div className="text-blue-300">Auto follow-up sent</div>
                  <div className="text-xs text-blue-500 mt-1">"Hi Sarah, checking in on bathroom quote"</div>
                </div>

                <div className="hidden sm:block text-slate-600">→</div>

                <div className="flex-shrink-0 bg-green-900/30 border border-green-500/30 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-green-400 mb-1">Thursday</div>
                  <div className="text-green-300">Sarah replies</div>
                  <div className="text-xs text-green-500 mt-1">"Yes, let's go ahead!"</div>
                </div>

                <div className="hidden sm:block text-slate-600">→</div>

                <div className="flex-shrink-0 bg-green-900/30 border border-green-500/30 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-green-400 mb-1">Result</div>
                  <div className="text-green-300">Job booked</div>
                  <div className="text-xs text-green-500 mt-1">$8,500 secured</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-24 bg-slate-900/50">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">How it works</h2>
            <p className="text-xl text-slate-300">Set it once. Forget about it. Win more jobs.</p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-r from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mb-6 mx-auto">
                1
              </div>
              <h3 className="text-xl font-semibold mb-4">Send quote as normal</h3>
              <p className="text-slate-300">
                Use your existing process. Email, text, or hand-deliver your quotes like you always do.
              </p>
            </div>

            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-r from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mb-6 mx-auto">
                2
              </div>
              <h3 className="text-xl font-semibold mb-4">AI follows up via SMS + email</h3>
              <p className="text-slate-300">
                Smart timing ensures your follow-ups feel natural and professional, not pushy.
              </p>
            </div>

            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-r from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mb-6 mx-auto">
                3
              </div>
              <h3 className="text-xl font-semibold mb-4">Get notified when ready to book</h3>
              <p className="text-slate-300">Instant alerts when customers respond. Strike while the iron's hot.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Founding Member Offer */}
      <section className="py-24">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Founding Member Offer</h2>
            <p className="text-xl text-slate-300">Get set up fast with a 14-day paid pilot, then lock in founder pricing.</p>
          </div>

          <div className="grid lg:grid-cols-3 gap-8 items-start">
            {/* Pricing tiers */}
            <div className="lg:col-span-2">
              <div className="grid md:grid-cols-3 gap-6">
                {[
                  {
                    name: 'Starter',
                    price: '$249',
                    desc: 'For solo tradies',
                    bullets: ['SMS + email follow-ups', 'Basic quote tracking', 'Weekly summary'],
                  },
                  {
                    name: 'Growth',
                    price: '$399',
                    desc: 'For growing teams',
                    bullets: ['Everything in Starter', 'More follow-up sequences', 'Priority support'],
                    featured: true,
                  },
                  {
                    name: 'Pro',
                    price: '$599',
                    desc: 'For busy operators',
                    bullets: ['Everything in Growth', 'Multi-user access', 'Advanced alerts + rules'],
                  },
                ].map((tier) => (
                  <div
                    key={tier.name}
                    className={`bg-slate-800/30 backdrop-blur-sm border rounded-xl p-6 transition-all ${
                      tier.featured
                        ? 'border-blue-500/40 shadow-[0_0_0_1px_rgba(59,130,246,0.15)]'
                        : 'border-slate-700/50'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-3 mb-4">
                      <h3 className="text-xl font-semibold">{tier.name}</h3>
                      {tier.featured && (
                        <span className="text-xs px-2 py-1 rounded-full bg-blue-500/15 text-blue-300 border border-blue-500/20">
                          Most popular
                        </span>
                      )}
                    </div>
                    <div className="text-3xl font-bold mb-1">
                      {tier.price}
                      <span className="text-base font-medium text-slate-400">/mo</span>
                    </div>
                    <div className="text-sm text-slate-400 mb-5">{tier.desc}</div>
                    <ul className="space-y-2 text-sm text-slate-300">
                      {tier.bullets.map((b) => (
                        <li key={b} className="flex items-start gap-2">
                          <span className="text-green-400 mt-0.5">✓</span>
                          <span>{b}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                ))}
              </div>

              <div className="mt-6 text-sm text-slate-400">
                Pricing tiers shown are planned monthly plans after launch.
              </div>
            </div>

            {/* Founding offer card */}
            <div className="bg-gradient-to-b from-blue-500/10 to-purple-500/10 border border-blue-500/20 rounded-xl p-6">
              <div className="flex items-center justify-between gap-3 mb-4">
                <h3 className="text-xl font-semibold">Founder pilot (first 20)</h3>
                <span className="text-xs px-2 py-1 rounded-full bg-blue-500/15 text-blue-300 border border-blue-500/20">
                  Limited
                </span>
              </div>

              <div className="text-slate-300 leading-relaxed">
                <div className="text-3xl font-bold text-white">
                  $500 <span className="text-base font-medium text-slate-300">deposit</span>
                </div>
                <div className="mt-2 text-sm text-slate-300">+ $299/mo for 6 months</div>

                <div className="mt-5 space-y-2 text-sm">
                  <div className="flex items-start gap-2">
                    <span className="text-blue-300 mt-0.5">•</span>
                    <span>14-day paid pilot — setup + follow-up sequences + alerts</span>
                  </div>
                  <div className="flex items-start gap-2">
                    <span className="text-blue-300 mt-0.5">•</span>
                    <span>We tailor the follow-ups to your trade + tone</span>
                  </div>
                  <div className="flex items-start gap-2">
                    <span className="text-blue-300 mt-0.5">•</span>
                    <span className="font-medium text-slate-200">
                      Guarantee: if we can’t get you live and showing value in 14 days, we’ll refund the deposit.
                    </span>
                  </div>
                </div>
              </div>

              <div className="mt-6 flex flex-col gap-3">
                <a
                  href={calendlyUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center justify-center px-5 py-3 bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700 rounded-lg font-medium transition-all"
                >
                  Book call
                </a>
                <a
                  href="#waitlist"
                  className="inline-flex items-center justify-center px-5 py-3 bg-slate-800/60 hover:bg-slate-800 border border-slate-700 rounded-lg font-medium transition-all"
                >
                  Request early access
                </a>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-24">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Everything you need</h2>
            <p className="text-xl text-slate-300">Built specifically for Australian tradies</p>
          </div>

          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-8">
            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-3xl mb-4">🤖</div>
              <h3 className="text-xl font-semibold mb-3">Auto Follow-Up</h3>
              <p className="text-slate-300">Intelligent follow-ups that sound like you wrote them. No robotic messages.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-3xl mb-4">📱</div>
              <h3 className="text-xl font-semibold mb-3">SMS + Email</h3>
              <p className="text-slate-300">Reach customers where they are. Multi-channel follow-ups increase response rates.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-3xl mb-4">⏰</div>
              <h3 className="text-xl font-semibold mb-3">Smart Timing</h3>
              <p className="text-slate-300">Follows up at the perfect moment. Not too early, not too late.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-3xl mb-4">📊</div>
              <h3 className="text-xl font-semibold mb-3">Quote Tracking</h3>
              <p className="text-slate-300">See which quotes are hot, cold, or ready to close. Never lose track again.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-3xl mb-4">📈</div>
              <h3 className="text-xl font-semibold mb-3">Win/Loss Analytics</h3>
              <p className="text-slate-300">Understand what's working. Improve your quote-to-job conversion rate.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-3xl mb-4">🔗</div>
              <h3 className="text-xl font-semibold mb-3">CRM Sync</h3>
              <p className="text-slate-300">Works with your existing tools. No need to change your workflow.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="py-24 bg-slate-900/50">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-8">
            <div className="text-4xl mb-6">🇦🇺</div>
            <h2 className="text-2xl font-bold mb-4">Built for Australian construction</h2>
            <p className="text-lg text-slate-300 mb-6">
              We understand the unique challenges of running a trade business in Australia. From compliance requirements
              to customer expectations, QuoteFollow is designed with local tradies in mind.
            </p>
            <div className="flex flex-wrap justify-center gap-4">
              <span className="px-3 py-1 bg-blue-500/20 text-blue-300 rounded-full text-sm">Australian English</span>
              <span className="px-3 py-1 bg-blue-500/20 text-blue-300 rounded-full text-sm">Local Business Hours</span>
              <span className="px-3 py-1 bg-blue-500/20 text-blue-300 rounded-full text-sm">Industry Compliant</span>
              <span className="px-3 py-1 bg-blue-500/20 text-blue-300 rounded-full text-sm">Tradie-Tested</span>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-24">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Common questions</h2>
            <p className="text-xl text-slate-300">Everything you need to know</p>
          </div>

          <div className="space-y-4">
            {[
              {
                question: "How does QuoteFollow know when I've sent a quote?",
                answer:
                  "You can forward quotes to QuoteFollow, or we integrate with popular quoting tools. We're also building direct integrations with major trade software platforms.",
              },
              {
                question: "Will customers know it's automated?",
                answer:
                  "No. Our AI writes follow-ups that sound natural and personal. Customers think you're just really good at staying in touch.",
              },
              {
                question: 'What if a customer replies to a follow-up?',
                answer:
                  'You get an instant notification. All replies come straight to you, so you can jump in and close the deal.',
              },
              {
                question: 'Can I customise the follow-up messages?',
                answer:
                  'Absolutely. You can set your tone, add your business details, and even create templates for different types of jobs.',
              },
              {
                question: 'When will QuoteFollow be available?',
                answer: "We're launching in early 2025. Waitlist members get first access and special launch pricing.",
              },
            ].map((faq, index) => (
              <div
                key={index}
                className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl overflow-hidden"
              >
                <button
                  onClick={() => toggleFaq(index)}
                  className="w-full px-6 py-4 text-left flex items-center justify-between hover:bg-slate-700/30 transition-all"
                >
                  <span className="font-semibold">{faq.question}</span>
                  <span className={`transform transition-transform ${openFaq === index ? 'rotate-180' : ''}`}>↓</span>
                </button>
                {openFaq === index && (
                  <div className="px-6 pb-4">
                    <p className="text-slate-300">{faq.answer}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA / Waitlist */}
      <section id="waitlist" className="py-24 bg-gradient-to-r from-blue-500/10 via-purple-500/10 to-blue-500/10">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-3xl sm:text-4xl font-bold mb-4">Don't lose another job to silence</h2>
          <p className="text-xl text-slate-300 mb-8">Join the waitlist now. Limited spots available for our early access program.</p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-3 mb-6">
            <a
              href={calendlyUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center px-6 py-3 bg-slate-800/60 hover:bg-slate-800 border border-slate-700 rounded-lg font-medium transition-all"
            >
              Book a 15-min call
            </a>
            <span className="text-sm text-slate-400">or request early access below</span>
          </div>

          <form onSubmit={(e) => handleSubmit(e, 'final-cta')} className="max-w-md mx-auto mb-8">
            <div className="flex flex-col sm:flex-row gap-3">
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="Enter your email"
                className="flex-1 px-4 py-3 rounded-lg bg-slate-800/50 border border-slate-700 backdrop-blur-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                required
              />
              <button
                type="submit"
                disabled={isSubmitting}
                className="px-6 py-3 bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700 rounded-lg font-medium transition-all transform hover:scale-105 disabled:opacity-50 disabled:transform-none"
              >
                {isSubmitting ? 'Joining...' : 'Secure My Spot'}
              </button>
            </div>
            {submitMessage && (
              <p className={`mt-3 text-sm ${submitMessage.includes('Thanks') ? 'text-green-400' : 'text-red-400'}`}>
                {submitMessage}
              </p>
            )}
          </form>

          <div className="text-sm text-slate-400">⚡ Request early access — limited spots available</div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-8 border-t border-slate-800">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <p className="text-slate-400">
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
