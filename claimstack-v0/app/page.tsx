'use client'

import { useState } from 'react'
import { Geist } from 'next/font/google'

const geist = Geist({ subsets: ['latin'] })

export default function Page() {
  const [email, setEmail] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [isSubmitted, setIsSubmitted] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setIsSubmitting(true)

    try {
      await fetch('https://script.google.com/macros/s/AKfycbzGVnBMK_A0suhhDRFnAh5LmxPRPKRBIb2ElAiE1npAIZBTvOWNPkYSoA3J5tCYx0E/exec', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email,
          product: 'claimstack'
        })
      })
      setIsSubmitted(true)
      setEmail('')
    } catch (error) {
      console.error('Error submitting email:', error)
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <div className={`${geist.className} min-h-screen bg-slate-950 text-white`}>
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-blue-600/20 via-slate-950 to-slate-950" />
        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-20 pb-24">
          <div className="text-center">
            <div className="inline-flex items-center px-4 py-2 rounded-full bg-blue-600/10 border border-blue-600/20 text-blue-400 text-sm font-medium mb-8">
              🇦🇺 Built for Australian subcontractors
            </div>
            <h1 className="text-5xl md:text-7xl font-bold tracking-tight mb-6">
              Get paid on time,
              <span className="text-blue-400"> every time</span>
            </h1>
            <p className="text-xl md:text-2xl text-slate-300 mb-12 max-w-3xl mx-auto">
              Stop chasing builders for payment. Submit compliant progress claims, track variations, and forecast your cash flow like a pro.
            </p>
            
            {/* Waitlist Form */}
            <div className="max-w-md mx-auto">
              {isSubmitted ? (
                <div className="bg-green-600/10 border border-green-600/20 rounded-lg p-4 text-green-400">
                  ✓ You're on the list! We'll be in touch soon.
                </div>
              ) : (
                <form onSubmit={handleSubmit} className="flex gap-3">
                  <input
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="Enter your email"
                    required
                    className="flex-1 px-4 py-3 bg-slate-800 border border-slate-700 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                  <button
                    type="submit"
                    disabled={isSubmitting}
                    className="px-6 py-3 bg-blue-600 hover:bg-blue-700 disabled:opacity-50 rounded-lg font-semibold transition-colors"
                  >
                    {isSubmitting ? 'Joining...' : 'Join Waitlist'}
                  </button>
                </form>
              )}
              <p className="text-sm text-slate-400 mt-3">
                Free for your first project. No credit card required.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Pain Points Section */}
      <section className="py-24 bg-slate-900/50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold mb-4">
              Sound familiar?
            </h2>
            <p className="text-xl text-slate-300">
              You're not alone. These are the top complaints we hear from tradies every day.
            </p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-8">
              <div className="text-red-400 text-4xl mb-4">😤</div>
              <h3 className="text-xl font-semibold mb-3">
                "Finished work 3 weeks ago, still chasing the builder for progress payment"
              </h3>
              <p className="text-slate-300">
                You've done the work, but getting paid feels like a full-time job. Phone calls, emails, excuses.
              </p>
            </div>
            
            <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-8">
              <div className="text-red-400 text-4xl mb-4">❌</div>
              <h3 className="text-xl font-semibold mb-3">
                "Payment claim rejected because a variation was missed — now wait another 30 days"
              </h3>
              <p className="text-slate-300">
                One small mistake and your claim gets bounced back. Meanwhile, your bills don't wait.
              </p>
            </div>
            
            <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-8">
              <div className="text-red-400 text-4xl mb-4">💸</div>
              <h3 className="text-xl font-semibold mb-3">
                "Doing $80K months but bank account says $12K because everyone pays 60-90 days late"
              </h3>
              <p className="text-slate-300">
                You're busy and profitable on paper, but cash flow is killing you. Sound about right?
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="py-24">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold mb-4">
              Everything you need to get paid properly
            </h2>
            <p className="text-xl text-slate-300">
              Built specifically for Australian subcontractors who are sick of payment headaches.
            </p>
          </div>
          
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div className="bg-slate-800/30 border border-slate-700 rounded-xl p-8 hover:bg-slate-800/50 transition-colors">
              <div className="w-12 h-12 bg-blue-600/20 rounded-lg flex items-center justify-center mb-6">
                <span className="text-2xl">📋</span>
              </div>
              <h3 className="text-xl font-semibold mb-3">Claim Builder</h3>
              <p className="text-slate-300">
                Walk through line items, mark percentage complete, add variations. Compliant with Security of Payment Act before hitting send.
              </p>
            </div>
            
            <div className="bg-slate-800/30 border border-slate-700 rounded-xl p-8 hover:bg-slate-800/50 transition-colors">
              <div className="w-12 h-12 bg-blue-600/20 rounded-lg flex items-center justify-center mb-6">
                <span className="text-2xl">📸</span>
              </div>
              <h3 className="text-xl font-semibold mb-3">Variation Tracker</h3>
              <p className="text-slate-300">
                Log variations with photos, emails, sign-off. Never miss one again. Your evidence is always organized and ready.
              </p>
            </div>
            
            <div className="bg-slate-800/30 border border-slate-700 rounded-xl p-8 hover:bg-slate-800/50 transition-colors">
              <div className="w-12 h-12 bg-blue-600/20 rounded-lg flex items-center justify-center mb-6">
                <span className="text-2xl">📅</span>
              </div>
              <h3 className="text-xl font-semibold mb-3">Payment Calendar</h3>
              <p className="text-slate-300">
                See when each claim is due, submitted, and when payment arrives. Chase late payers with one tap.
              </p>
            </div>
            
            <div className="bg-slate-800/30 border border-slate-700 rounded-xl p-8 hover:bg-slate-800/50 transition-colors">
              <div className="w-12 h-12 bg-blue-600/20 rounded-lg flex items-center justify-center mb-6">
                <span className="text-2xl">🛡️</span>
              </div>
              <h3 className="text-xl font-semibold mb-3">Rejection Shield</h3>
              <p className="text-slate-300">
                Pre-checks claims against common rejection reasons before submission. No more bounced claims.
              </p>
            </div>
            
            <div className="bg-slate-800/30 border border-slate-700 rounded-xl p-8 hover:bg-slate-800/50 transition-colors">
              <div className="w-12 h-12 bg-blue-600/20 rounded-lg flex items-center justify-center mb-6">
                <span className="text-2xl">💰</span>
              </div>
              <h3 className="text-xl font-semibold mb-3">Cash Flow Forecast</h3>
              <p className="text-slate-300">
                90-day income forecast based on open claims and project schedules. Plan ahead like a pro.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works Section */}
      <section className="py-24 bg-slate-900/50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold mb-4">
              How it works
            </h2>
            <p className="text-xl text-slate-300">
              Three simple steps to never chase a payment again.
            </p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            <div className="text-center">
              <div className="w-16 h-16 bg-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mx-auto mb-6">
                1
              </div>
              <h3 className="text-xl font-semibold mb-3">Set up contract</h3>
              <p className="text-slate-300">
                5 minutes per project. Add your contract details, payment schedule, and you're ready to go.
              </p>
            </div>
            
            <div className="text-center">
              <div className="w-16 h-16 bg-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mx-auto mb-6">
                2
              </div>
              <h3 className="text-xl font-semibold mb-3">Submit claims monthly</h3>
              <p className="text-slate-300">
                Progress, variations, evidence. Security of Payment Act compliant every time. No more rejected claims.
              </p>
            </div>
            
            <div className="text-center">
              <div className="w-16 h-16 bg-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mx-auto mb-6">
                3
              </div>
              <h3 className="text-xl font-semibold mb-3">Track and get paid</h3>
              <p className="text-slate-300">
                Monitor payment status, chase late payers, and forecast your cash flow. Get paid on time, every time.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Pricing Section */}
      <section className="py-24">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold mb-4">
              Simple pricing that makes sense
            </h2>
            <p className="text-xl text-slate-300">
              Start free, upgrade when you need more projects.
            </p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8 max-w-5xl mx-auto">
            <div className="bg-slate-800/30 border border-slate-700 rounded-xl p-8">
              <h3 className="text-xl font-semibold mb-2">Starter</h3>
              <div className="text-3xl font-bold mb-4">
                $0<span className="text-lg text-slate-400">/month</span>
              </div>
              <p className="text-slate-300 mb-6">Perfect for trying us out</p>
              <ul className="space-y-3 mb-8">
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  1 project
                </li>
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  Basic claim builder
                </li>
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  Payment tracking
                </li>
              </ul>
              <button className="w-full py-3 border border-slate-600 rounded-lg hover:bg-slate-800 transition-colors">
                Start Free
              </button>
            </div>
            
            <div className="bg-blue-600/10 border-2 border-blue-600 rounded-xl p-8 relative">
              <div className="absolute -top-4 left-1/2 transform -translate-x-1/2">
                <span className="bg-blue-600 text-white px-4 py-1 rounded-full text-sm font-medium">
                  Most Popular
                </span>
              </div>
              <h3 className="text-xl font-semibold mb-2">Tradie</h3>
              <div className="text-3xl font-bold mb-4">
                $49<span className="text-lg text-slate-400">/month</span>
              </div>
              <p className="text-slate-300 mb-6">For serious subcontractors</p>
              <ul className="space-y-3 mb-8">
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  10 projects
                </li>
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  All features included
                </li>
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  Variation tracker
                </li>
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  Cash flow forecast
                </li>
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  Email support
                </li>
              </ul>
              <button className="w-full py-3 bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors">
                Join Waitlist
              </button>
            </div>
            
            <div className="bg-slate-800/30 border border-slate-700 rounded-xl p-8">
              <h3 className="text-xl font-semibold mb-2">Builder</h3>
              <div className="text-3xl font-bold mb-4">
                $99<span className="text-lg text-slate-400">/month</span>
              </div>
              <p className="text-slate-300 mb-6">For growing businesses</p>
              <ul className="space-y-3 mb-8">
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  Unlimited projects
                </li>
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  Team collaboration
                </li>
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  Xero integration
                </li>
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  Priority support
                </li>
                <li className="flex items-center">
                  <span className="text-green-400 mr-3">✓</span>
                  Custom reporting
                </li>
              </ul>
              <button className="w-full py-3 border border-slate-600 rounded-lg hover:bg-slate-800 transition-colors">
                Join Waitlist
              </button>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ Section */}
      <section className="py-24 bg-slate-900/50">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold mb-4">
              Frequently asked questions
            </h2>
          </div>
          
          <div className="space-y-8">
            <div className="bg-slate-800/30 border border-slate-700 rounded-xl p-8">
              <h3 className="text-xl font-semibold mb-3">
                Is this compliant with Australian Security of Payment laws?
              </h3>
              <p className="text-slate-300">
                Absolutely. ClaimStack is built specifically for Australian subcontractors and ensures all claims meet Security of Payment Act requirements across all states.
              </p>
            </div>
            
            <div className="bg-slate-800/30 border border-slate-700 rounded-xl p-8">
              <h3 className="text-xl font-semibold mb-3">
                What if I'm not tech-savvy?
              </h3>
              <p className="text-slate-300">
                ClaimStack is designed for tradies, not tech experts. If you can send a text message, you can use ClaimStack. Plus, we provide full onboarding support.
              </p>
            </div>
            
            <div className="bg-slate-800/30 border border-slate-700 rounded-xl p-8">
              <h3 className="text-xl font-semibold mb-3">
                Can I import my existing contracts?
              </h3>
              <p className="text-slate-300">
                Yes! We'll help you import your existing contracts and set up your payment schedules. Our team handles the heavy lifting during onboarding.
              </p>
            </div>
            
            <div className="bg-slate-800/30 border border-slate-700 rounded-xl p-8">
              <h3 className="text-xl font-semibold mb-3">
                What about Xero integration?
              </h3>
              <p className="text-slate-300">
                Available on the Builder plan. Automatically sync your approved claims to Xero, so your books stay up to date without double entry.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-12 border-t border-slate-800">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex flex-col md:flex-row justify-between items-center">
            <div className="mb-4 md:mb-0">
              <h3 className="text-2xl font-bold text-blue-400">ClaimStack</h3>
              <p className="text-slate-400">Get paid on time, every time.</p>
            </div>
            <div className="text-slate-400">
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
          </div>
        </div>
      </footer>
    </div>
  )
}
