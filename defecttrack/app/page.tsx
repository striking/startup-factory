'use client'

import { Geist } from 'next/font/google'
import { Analytics } from '@vercel/analytics/react'
import { useState } from 'react'

const geist = Geist({ subsets: ['latin'] })

export default function Page() {
  const [email, setEmail] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [isSubmitted, setIsSubmitted] = useState(false)
  const [openFaq, setOpenFaq] = useState<number | null>(null)

  // Waitlist API endpoint - deployed Google Apps Script web app
  const WAITLIST_API_URL = "/api/waitlist";

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email || isSubmitting) return

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
          email: email,
          product: 'defecttrack',
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

  const toggleFaq = (index: number) => {
    setOpenFaq(openFaq === index ? null : index)
  }

  return (
    <div className={`${geist.className} min-h-screen bg-slate-950 text-white`}>
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-red-500/10 via-transparent to-transparent"></div>
        <div className="relative max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 pt-20 pb-32">
          <div className="text-center max-w-4xl mx-auto">
            <div className="inline-flex items-center px-4 py-2 rounded-full bg-red-500/10 border border-red-500/20 backdrop-blur-sm mb-8">
              <span className="text-red-400 text-sm font-medium">🚀 Invitation Only — Early Access</span>
            </div>
            
            <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold mb-6 bg-gradient-to-r from-white via-slate-200 to-slate-400 bg-clip-text text-transparent">
              AI defect lists that close themselves
            </h1>
            
            <p className="text-xl sm:text-2xl text-slate-300 mb-12 leading-relaxed">
              Stop chasing trades. Stop losing track. DefectTrack turns chaos into completion for Australian builders.
            </p>

            <form onSubmit={handleSubmit} className="max-w-md mx-auto mb-12">
              <div className="flex flex-col sm:flex-row gap-4">
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="your@email.com.au"
                  className="flex-1 px-6 py-4 rounded-xl bg-slate-800/50 border border-slate-700 backdrop-blur-sm focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-transparent transition-all duration-200"
                  required
                />
                <button
                  type="submit"
                  disabled={isSubmitting || isSubmitted}
                  className="px-8 py-4 bg-gradient-to-r from-red-500 to-red-600 hover:from-red-600 hover:to-red-700 rounded-xl font-semibold transition-all duration-200 transform hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none"
                >
                  {isSubmitted ? '✓ You\'re in!' : isSubmitting ? 'Joining...' : 'Request Early Access'}
                </button>
              </div>
            </form>

            <div className="flex items-center justify-center gap-8 text-slate-400">
              <div className="flex items-center gap-2">
                <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
                <span className="text-sm">Early access open</span>
              </div>
              <div className="w-px h-4 bg-slate-700"></div>
              <span className="text-sm">🇦🇺 Built for Australian construction</span>
            </div>
          </div>
        </div>
      </section>

      {/* Problem Section */}
      <section className="py-24 px-4 sm:px-6 lg:px-8">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Sound familiar?</h2>
            <p className="text-xl text-slate-400">Every builder knows these headaches</p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-8 hover:border-slate-700 transition-all duration-300">
              <div className="text-4xl mb-4">📧</div>
              <blockquote className="text-lg text-slate-300 italic leading-relaxed">
                "Handover defect list sitting in email for 3 weeks. Nobody knows what's done."
              </blockquote>
            </div>

            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-8 hover:border-slate-700 transition-all duration-300">
              <div className="text-4xl mb-4">📊</div>
              <blockquote className="text-lg text-slate-300 italic leading-relaxed">
                "Tracking system is a spreadsheet 4 people edit. Nobody trusts it."
              </blockquote>
            </div>

            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-8 hover:border-slate-700 transition-all duration-300">
              <div className="text-4xl mb-4">🚗</div>
              <blockquote className="text-lg text-slate-300 italic leading-relaxed">
                "Every trip back to site costs $200+. Half the time subbie hasn't even started."
              </blockquote>
            </div>
          </div>
        </div>
      </section>

      {/* Show Don't Tell Section */}
      <section className="py-24 px-4 sm:px-6 lg:px-8 bg-slate-900/30">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">From chaos to clarity</h2>
            <p className="text-xl text-slate-400">See the difference in 3 seconds</p>
          </div>

          <div className="grid lg:grid-cols-2 gap-12 items-center">
            {/* Before - Email Chaos */}
            <div className="space-y-4">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 bg-red-500/20 rounded-full flex items-center justify-center">
                  <span className="text-red-400 font-bold text-sm">❌</span>
                </div>
                <h3 className="text-2xl font-bold text-red-400">Before: Email Hell</h3>
              </div>

              <div className="bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-xl overflow-hidden">
                <div className="bg-slate-700/50 px-4 py-3 border-b border-slate-600">
                  <div className="text-sm font-medium">RE: RE: RE: Defect List — 42 Maple St</div>
                  <div className="text-xs text-slate-400">47 messages, 12 participants</div>
                </div>
                
                <div className="p-4 space-y-3 max-h-80 overflow-y-auto">
                  <div className="bg-slate-700/30 rounded-lg p-3">
                    <div className="text-sm font-medium text-slate-300 mb-1">Dave (Plumber)</div>
                    <div className="text-sm text-slate-400">"Which crack? The one near the window or the other one?"</div>
                  </div>
                  
                  <div className="bg-slate-700/30 rounded-lg p-3">
                    <div className="text-sm font-medium text-slate-300 mb-1">Sarah (PM)</div>
                    <div className="text-sm text-slate-400">"Thought that was done? See attached list v3 FINAL FINAL"</div>
                  </div>
                  
                  <div className="bg-slate-700/30 rounded-lg p-3">
                    <div className="text-sm font-medium text-slate-300 mb-1">Mike (Sparky)</div>
                    <div className="text-sm text-slate-400">"Can't open the attachment. Which version are we using?"</div>
                  </div>
                  
                  <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-3">
                    <div className="text-sm font-medium text-red-400 mb-1">Status: Unknown</div>
                    <div className="text-xs text-slate-400">Last update: 3 weeks ago</div>
                  </div>
                </div>
              </div>
            </div>

            {/* After - Clean Dashboard */}
            <div className="space-y-4">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 bg-green-500/20 rounded-full flex items-center justify-center">
                  <span className="text-green-400 font-bold text-sm">✓</span>
                </div>
                <h3 className="text-2xl font-bold text-green-400">After: DefectTrack</h3>
              </div>

              <div className="bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-xl overflow-hidden">
                <div className="bg-slate-700/50 px-4 py-3 border-b border-slate-600">
                  <div className="text-sm font-medium">42 Maple St — Defect Dashboard</div>
                  <div className="text-xs text-slate-400">Updated 2 minutes ago</div>
                </div>
                
                <div className="p-4 space-y-4">
                  <div className="flex items-center justify-between mb-4">
                    <span className="text-sm text-slate-400">Progress</span>
                    <span className="text-sm font-medium">65% Complete</span>
                  </div>
                  <div className="w-full bg-slate-700 rounded-full h-2">
                    <div className="bg-gradient-to-r from-green-500 to-green-400 h-2 rounded-full" style={{width: '65%'}}></div>
                  </div>
                  
                  <div className="space-y-3">
                    <div className="flex items-center justify-between p-3 bg-green-500/10 border border-green-500/20 rounded-lg">
                      <div className="flex items-center gap-3">
                        <div className="w-2 h-2 bg-green-500 rounded-full"></div>
                        <span className="text-sm">Kitchen tap leak</span>
                      </div>
                      <span className="px-2 py-1 bg-green-500/20 text-green-400 text-xs rounded-full">Completed</span>
                    </div>
                    
                    <div className="flex items-center justify-between p-3 bg-green-500/10 border border-green-500/20 rounded-lg">
                      <div className="flex items-center gap-3">
                        <div className="w-2 h-2 bg-green-500 rounded-full"></div>
                        <span className="text-sm">Bathroom door alignment</span>
                      </div>
                      <span className="px-2 py-1 bg-green-500/20 text-green-400 text-xs rounded-full">Completed</span>
                    </div>
                    
                    <div className="flex items-center justify-between p-3 bg-amber-500/10 border border-amber-500/20 rounded-lg">
                      <div className="flex items-center gap-3">
                        <div className="w-2 h-2 bg-amber-500 rounded-full"></div>
                        <span className="text-sm">Paint touch-up hallway</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="text-xs text-slate-400">Dave (Painter)</span>
                        <span className="px-2 py-1 bg-amber-500/20 text-amber-400 text-xs rounded-full">In Progress</span>
                      </div>
                    </div>
                    
                    <div className="flex items-center justify-between p-3 bg-red-500/10 border border-red-500/20 rounded-lg">
                      <div className="flex items-center gap-3">
                        <div className="w-2 h-2 bg-red-500 rounded-full"></div>
                        <span className="text-sm">Electrical outlet bedroom 2</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="text-xs text-slate-400">12 days</span>
                        <span className="px-2 py-1 bg-red-500/20 text-red-400 text-xs rounded-full">Overdue</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-24 px-4 sm:px-6 lg:px-8">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">How it works</h2>
            <p className="text-xl text-slate-400">Three steps to defect-free handovers</p>
          </div>

          <div className="grid md:grid-cols-3 gap-12">
            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-br from-red-500 to-red-600 rounded-2xl flex items-center justify-center text-2xl font-bold mb-6 mx-auto">
                1
              </div>
              <h3 className="text-xl font-bold mb-4">Walk & Talk</h3>
              <p className="text-slate-400 leading-relaxed">
                Walk the site, voice-tag defects with photos. No typing, no forms. Just point, speak, snap.
              </p>
            </div>

            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-br from-red-500 to-red-600 rounded-2xl flex items-center justify-center text-2xl font-bold mb-6 mx-auto">
                2
              </div>
              <h3 className="text-xl font-bold mb-4">AI Sorts It</h3>
              <p className="text-slate-400 leading-relaxed">
                AI generates the list, assigns the right trades, sends notifications. Everyone knows what to do.
              </p>
            </div>

            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-br from-red-500 to-red-600 rounded-2xl flex items-center justify-center text-2xl font-bold mb-6 mx-auto">
                3
              </div>
              <h3 className="text-xl font-bold mb-4">Proof & Close</h3>
              <p className="text-slate-400 leading-relaxed">
                Trades upload photo proof when fixed. You verify and close. No more guessing games.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-24 px-4 sm:px-6 lg:px-8 bg-slate-900/30">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Everything you need</h2>
            <p className="text-xl text-slate-400">Built for how Australian builders actually work</p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div className="bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-2xl p-8 hover:border-slate-600 transition-all duration-300">
              <div className="text-3xl mb-4">🎤</div>
              <h3 className="text-xl font-bold mb-3">Voice + Photo Logging</h3>
              <p className="text-slate-400">Speak your defects while taking photos. No typing on site.</p>
            </div>

            <div className="bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-2xl p-8 hover:border-slate-600 transition-all duration-300">
              <div className="text-3xl mb-4">🎯</div>
              <h3 className="text-xl font-bold mb-3">Auto-Assignment</h3>
              <p className="text-slate-400">AI assigns defects to the right trades automatically. No manual sorting.</p>
            </div>

            <div className="bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-2xl p-8 hover:border-slate-600 transition-all duration-300">
              <div className="text-3xl mb-4">📱</div>
              <h3 className="text-xl font-bold mb-3">Trade Notifications</h3>
              <p className="text-slate-400">Trades get notified instantly with photos and clear descriptions.</p>
            </div>

            <div className="bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-2xl p-8 hover:border-slate-600 transition-all duration-300">
              <div className="text-3xl mb-4">📸</div>
              <h3 className="text-xl font-bold mb-3">Photo Proof</h3>
              <p className="text-slate-400">Before and after photos for every defect. Visual proof of completion.</p>
            </div>

            <div className="bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-2xl p-8 hover:border-slate-600 transition-all duration-300">
              <div className="text-3xl mb-4">🔍</div>
              <h3 className="text-xl font-bold mb-3">Re-Inspection Tracker</h3>
              <p className="text-slate-400">Track what needs checking again. Never miss a follow-up.</p>
            </div>

            <div className="bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-2xl p-8 hover:border-slate-600 transition-all duration-300">
              <div className="text-3xl mb-4">📊</div>
              <h3 className="text-xl font-bold mb-3">Reports</h3>
              <p className="text-slate-400">Professional reports for clients. Export to PDF with one click.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="py-24 px-4 sm:px-6 lg:px-8">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-3xl sm:text-4xl font-bold mb-8">Trusted by Australian builders</h2>
          
          <div className="grid md:grid-cols-3 gap-8 mb-12">
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-xl p-6">
              <div className="text-2xl font-bold text-red-400 mb-2">🇦🇺</div>
              <div className="text-sm text-slate-400">Built for Australian construction standards and workflows</div>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-xl p-6">
              <div className="text-2xl font-bold text-red-400 mb-2">⚡</div>
              <div className="text-sm text-slate-400">Works offline on site, syncs when you're back in range</div>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-xl p-6">
              <div className="text-2xl font-bold text-red-400 mb-2">🔒</div>
              <div className="text-sm text-slate-400">Australian data hosting, privacy compliant</div>
            </div>
          </div>

          <div className="bg-gradient-to-r from-slate-800/50 to-slate-900/50 backdrop-blur-sm border border-slate-700 rounded-2xl p-8">
            <blockquote className="text-xl text-slate-300 italic mb-4">
              "Finally, a defect system that actually works how we work. No more email chains, no more confusion."
            </blockquote>
            <div className="text-slate-400">
              — Early access builder (name withheld until launch)
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-24 px-4 sm:px-6 lg:px-8 bg-slate-900/30">
        <div className="max-w-4xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Common questions</h2>
            <p className="text-xl text-slate-400">Everything you need to know</p>
          </div>

          <div className="space-y-4">
            {[
              {
                question: "How does the voice logging actually work?",
                answer: "Just speak naturally while taking photos. 'Kitchen tap is dripping, needs new washer.' Our AI transcribes and categorises everything automatically. Works with Aussie accents too."
              },
              {
                question: "What if my trades don't use smartphones?",
                answer: "They don't need to. You can assign and track everything from your end. When they finish, they just text you a photo. We'll integrate it automatically."
              },
              {
                question: "Does it work without internet on site?",
                answer: "Absolutely. Log defects offline, everything syncs when you're back in range. Built for real construction sites, not perfect office conditions."
              },
              {
                question: "How much does it cost?",
                answer: "We're still finalising pricing based on early access feedback. Join the waitlist and you'll be first to know when we launch with special early bird rates."
              },
              {
                question: "When will it be available?",
                answer: "We're targeting early 2024 for the first release. Waitlist members get first access and help shape the final product."
              }
            ].map((faq, index) => (
              <div key={index} className="bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-xl overflow-hidden">
                <button
                  onClick={() => toggleFaq(index)}
                  className="w-full px-6 py-4 text-left flex items-center justify-between hover:bg-slate-700/30 transition-colors duration-200"
                >
                  <span className="font-semibold">{faq.question}</span>
                  <span className={`transform transition-transform duration-200 ${openFaq === index ? 'rotate-180' : ''}`}>
                    ↓
                  </span>
                </button>
                {openFaq === index && (
                  <div className="px-6 pb-4 text-slate-400 leading-relaxed">
                    {faq.answer}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="py-24 px-4 sm:px-6 lg:px-8">
        <div className="max-w-4xl mx-auto text-center">
          <div className="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-sm border border-slate-700 rounded-3xl p-12">
            <h2 className="text-3xl sm:text-4xl font-bold mb-6">
              Ready to close defects faster?
            </h2>
            <p className="text-xl text-slate-400 mb-8">
              Request early access. Limited spots available.
            </p>

            <form onSubmit={handleSubmit} className="max-w-md mx-auto mb-8">
              <div className="flex flex-col sm:flex-row gap-4">
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="your@email.com.au"
                  className="flex-1 px-6 py-4 rounded-xl bg-slate-800/50 border border-slate-700 backdrop-blur-sm focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-transparent transition-all duration-200"
                  required
                />
                <button
                  type="submit"
                  disabled={isSubmitting || isSubmitted}
                  className="px-8 py-4 bg-gradient-to-r from-red-500 to-red-600 hover:from-red-600 hover:to-red-700 rounded-xl font-semibold transition-all duration-200 transform hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none"
                >
                  {isSubmitted ? '✓ You\'re in!' : isSubmitting ? 'Joining...' : 'Get Early Access'}
                </button>
              </div>
            </form>

            <div className="flex items-center justify-center gap-4 text-sm text-slate-500">
              <span>⚡ No spam, just updates</span>
              <span>•</span>
              <span>🇦🇺 Australian owned</span>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-12 px-4 sm:px-6 lg:px-8 border-t border-slate-800">
        <div className="max-w-6xl mx-auto text-center">
          <p className="text-slate-500">
            Built by{' '}
            <a 
              href="https://levasolutions.com.au" 
              target="_blank" 
              rel="noopener noreferrer"
              className="text-red-400 hover:text-red-300 transition-colors duration-200"
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