'use client'

import { useState } from 'react'
import { Geist } from 'next/font/google'
import { Analytics } from '@vercel/analytics/react'

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
    if (!email) return

    setIsSubmitting(true)
    try {
      // Get UTM params from URL
      const urlParams = new URLSearchParams(window.location.search);

      await fetch(WAITLIST_API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email,
          product: 'safetalk',
          referrer: document.referrer || '',
          utmSource: urlParams.get('utm_source') || '',
          utmMedium: urlParams.get('utm_medium') || '',
          utmCampaign: urlParams.get('utm_campaign') || ''
        })
      })
      setIsSubmitted(true)
      setEmail('')
    } catch (error) {
      console.error('Submission error:', error)
    } finally {
      setIsSubmitting(false)
    }
  }

  const WaitlistForm = ({ showUrgency = false }: { showUrgency?: boolean }) => (
    <form onSubmit={handleSubmit} className="w-full max-w-md mx-auto">
      {isSubmitted ? (
        <div className="text-center p-6 bg-gradient-to-r from-green-500/10 to-emerald-500/10 border border-green-500/20 rounded-xl backdrop-blur-sm">
          <div className="text-2xl mb-2">✅</div>
          <p className="text-green-400 font-medium">You're on the list!</p>
          <p className="text-slate-400 text-sm mt-1">We'll be in touch soon.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {showUrgency && (
            <div className="text-center mb-4">
              <span className="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-gradient-to-r from-red-500/20 to-orange-500/20 text-red-300 border border-red-500/30">
                🔥 Limited early access spots
              </span>
            </div>
          )}
          <div className="flex flex-col sm:flex-row gap-3">
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="your.email@company.com.au"
              required
              className="flex-1 px-4 py-3 bg-slate-800/50 border border-slate-700 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-red-500/50 focus:border-red-500/50 backdrop-blur-sm transition-all duration-200"
            />
            <button
              type="submit"
              disabled={isSubmitting}
              className="px-6 py-3 bg-gradient-to-r from-red-500 to-red-600 text-white font-medium rounded-lg hover:from-red-600 hover:to-red-700 focus:outline-none focus:ring-2 focus:ring-red-500/50 disabled:opacity-50 disabled:cursor-not-allowed transition-all duration-200 transform hover:scale-105"
            >
              {isSubmitting ? 'Joining...' : 'Request Early Access'}
            </button>
          </div>
          <p className="text-xs text-slate-400 text-center">
            Invitation only. Australian construction sites first.
          </p>
        </div>
      )}
    </form>
  )

  return (
    <div className={`min-h-screen bg-slate-950 text-white ${geist.className}`}>
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-red-500/5 via-transparent to-orange-500/5"></div>
        <div className="relative max-w-6xl mx-auto px-4 py-16 sm:py-24">
          <div className="text-center space-y-8">
            <div className="space-y-4">
              <span className="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-gradient-to-r from-red-500/20 to-orange-500/20 text-red-300 border border-red-500/30">
                🚧 Built for Australian Construction
              </span>
              <h1 className="text-4xl sm:text-6xl lg:text-7xl font-bold tracking-tight">
                Toolbox talks that
                <span className="block bg-gradient-to-r from-red-400 to-orange-400 bg-clip-text text-transparent">
                  actually get done
                </span>
              </h1>
              <p className="text-xl sm:text-2xl text-slate-300 max-w-3xl mx-auto leading-relaxed">
                AI-generated daily safety briefings. Weather-aware. Trade-specific. 
                Digital sign-off. Ready by 6AM, every morning.
              </p>
            </div>

            <WaitlistForm />

            <div className="flex items-center justify-center space-x-8 text-sm text-slate-400">
              <div className="flex items-center space-x-2">
                <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
                <span>Early access open</span>
              </div>
              <div className="flex items-center space-x-2">
                <span>⚡</span>
                <span>Launching soon</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Problem Section */}
      <section className="py-16 sm:py-24">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              Sound familiar?
            </h2>
            <p className="text-xl text-slate-400">
              Every site manager knows these pain points
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6 backdrop-blur-sm hover:border-slate-700 transition-all duration-200">
              <div className="text-3xl mb-4">📋</div>
              <blockquote className="text-slate-300 italic mb-4">
                "Legally required daily toolbox talks. Recycling the same one from 3 months ago."
              </blockquote>
              <p className="text-sm text-slate-500">— Every site manager, ever</p>
            </div>

            <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6 backdrop-blur-sm hover:border-slate-700 transition-all duration-200">
              <div className="text-3xl mb-4">⏰</div>
              <blockquote className="text-slate-300 italic mb-4">
                "Writing a fresh safety briefing before 7am isn't happening. So we wing it."
              </blockquote>
              <p className="text-sm text-slate-500">— Honest site supervisor</p>
            </div>

            <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6 backdrop-blur-sm hover:border-slate-700 transition-all duration-200">
              <div className="text-3xl mb-4">📄</div>
              <blockquote className="text-slate-300 italic mb-4">
                "SafeWork shows up and asks for records. Scrambling through crumpled sign-off sheets."
              </blockquote>
              <p className="text-sm text-slate-500">— Stressed safety officer</p>
            </div>
          </div>
        </div>
      </section>

      {/* Show Don't Tell Section */}
      <section className="py-16 sm:py-24 bg-gradient-to-b from-slate-950 to-slate-900/50">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              See it in action
            </h2>
            <p className="text-xl text-slate-400">
              AI generates your toolbox talk in seconds
            </p>
          </div>

          <div className="max-w-4xl mx-auto">
            <div className="bg-slate-900/80 border border-slate-700 rounded-2xl p-8 backdrop-blur-sm">
              {/* Input Section */}
              <div className="mb-8">
                <h3 className="text-lg font-semibold mb-4 text-slate-300">Today's Conditions</h3>
                <div className="grid sm:grid-cols-2 gap-4">
                  <div className="bg-slate-800/50 border border-slate-600 rounded-lg p-4">
                    <label className="block text-sm font-medium text-slate-400 mb-2">Trade</label>
                    <div className="text-white font-medium">Roofing</div>
                  </div>
                  <div className="bg-slate-800/50 border border-slate-600 rounded-lg p-4">
                    <label className="block text-sm font-medium text-slate-400 mb-2">Weather</label>
                    <div className="text-white font-medium">High winds 35km/h</div>
                  </div>
                </div>
              </div>

              {/* Generated Output */}
              <div className="border-t border-slate-700 pt-8">
                <div className="flex items-center justify-between mb-6">
                  <h3 className="text-lg font-semibold text-slate-300">Generated Toolbox Talk</h3>
                  <span className="px-3 py-1 bg-green-500/20 text-green-400 text-sm rounded-full border border-green-500/30">
                    ✨ AI Generated
                  </span>
                </div>

                <div className="bg-white/5 border border-slate-600 rounded-xl p-6 space-y-6">
                  <div>
                    <h4 className="text-xl font-bold text-white mb-2">Working at Heights in High Wind</h4>
                    <p className="text-slate-400 text-sm">Generated for: Roofing • Date: {new Date().toLocaleDateString('en-AU')}</p>
                  </div>

                  <div>
                    <h5 className="font-semibold text-red-400 mb-3">⚠️ Key Risks Today</h5>
                    <ul className="space-y-2 text-slate-300">
                      <li className="flex items-start space-x-2">
                        <span className="text-red-400 mt-1">•</span>
                        <span>Wind gusts can exceed safe working limits (40km/h)</span>
                      </li>
                      <li className="flex items-start space-x-2">
                        <span className="text-red-400 mt-1">•</span>
                        <span>Unsecured materials becoming projectiles</span>
                      </li>
                      <li className="flex items-start space-x-2">
                        <span className="text-red-400 mt-1">•</span>
                        <span>Reduced ladder stability in gusty conditions</span>
                      </li>
                    </ul>
                  </div>

                  <div>
                    <h5 className="font-semibold text-green-400 mb-3">✅ Safety Controls</h5>
                    <ul className="space-y-2 text-slate-300">
                      <li className="flex items-start space-x-2">
                        <span className="text-green-400 mt-1">•</span>
                        <span>Suspend roof work if winds exceed 40km/h</span>
                      </li>
                      <li className="flex items-start space-x-2">
                        <span className="text-green-400 mt-1">•</span>
                        <span>Secure all loose materials before starting</span>
                      </li>
                      <li className="flex items-start space-x-2">
                        <span className="text-green-400 mt-1">•</span>
                        <span>Implement buddy system for all height work</span>
                      </li>
                    </ul>
                  </div>

                  <div className="border-t border-slate-600 pt-4">
                    <h5 className="font-semibold text-slate-300 mb-3">📝 Digital Sign-Off</h5>
                    <div className="bg-slate-800/50 rounded-lg p-4">
                      <p className="text-sm text-slate-400 mb-2">Crew members scan QR code to acknowledge:</p>
                      <div className="flex items-center space-x-4">
                        <div className="w-16 h-16 bg-white rounded-lg flex items-center justify-center">
                          <div className="w-12 h-12 bg-black rounded grid grid-cols-3 gap-px">
                            {[...Array(9)].map((_, i) => (
                              <div key={i} className={`${Math.random() > 0.5 ? 'bg-white' : 'bg-black'}`}></div>
                            ))}
                          </div>
                        </div>
                        <div className="text-sm text-slate-300">
                          <p>✅ 8 signatures collected</p>
                          <p className="text-slate-500">Automatically timestamped & stored</p>
                        </div>
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
      <section className="py-16 sm:py-24">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              How it works
            </h2>
            <p className="text-xl text-slate-400">
              Set it once, forget about it
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <div className="text-center space-y-4">
              <div className="w-16 h-16 bg-gradient-to-br from-red-500 to-orange-500 rounded-2xl flex items-center justify-center text-2xl font-bold mx-auto">
                1
              </div>
              <h3 className="text-xl font-semibold">Set up site + trades</h3>
              <p className="text-slate-400">
                Tell us your site details, trades, and typical hazards. Takes 5 minutes.
              </p>
            </div>

            <div className="text-center space-y-4">
              <div className="w-16 h-16 bg-gradient-to-br from-red-500 to-orange-500 rounded-2xl flex items-center justify-center text-2xl font-bold mx-auto">
                2
              </div>
              <h3 className="text-xl font-semibold">AI generates talk by 6AM</h3>
              <p className="text-slate-400">
                Every morning, fresh toolbox talk ready. Weather-aware, trade-specific, compliant.
              </p>
            </div>

            <div className="text-center space-y-4">
              <div className="w-16 h-16 bg-gradient-to-br from-red-500 to-orange-500 rounded-2xl flex items-center justify-center text-2xl font-bold mx-auto">
                3
              </div>
              <h3 className="text-xl font-semibold">Crew scans QR, signs off digitally</h3>
              <p className="text-slate-400">
                No more paper. Digital signatures, automatic records, compliance sorted.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-16 sm:py-24 bg-gradient-to-b from-slate-950 to-slate-900/50">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              Everything you need
            </h2>
            <p className="text-xl text-slate-400">
              Built for Australian construction sites
            </p>
          </div>

          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-8">
            <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6 backdrop-blur-sm hover:border-slate-700 transition-all duration-200">
              <div className="text-3xl mb-4">🤖</div>
              <h3 className="text-lg font-semibold mb-2">Daily Auto-Generate</h3>
              <p className="text-slate-400">Fresh toolbox talk every morning. Never repeat the same briefing.</p>
            </div>

            <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6 backdrop-blur-sm hover:border-slate-700 transition-all duration-200">
              <div className="text-3xl mb-4">🌤️</div>
              <h3 className="text-lg font-semibold mb-2">Weather-Aware</h3>
              <p className="text-slate-400">Automatically includes weather hazards and wind speed warnings.</p>
            </div>

            <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6 backdrop-blur-sm hover:border-slate-700 transition-all duration-200">
              <div className="text-3xl mb-4">📱</div>
              <h3 className="text-lg font-semibold mb-2">Digital Sign-Off</h3>
              <p className="text-slate-400">QR codes, digital signatures, automatic timestamping. No more paper.</p>
            </div>

            <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6 backdrop-blur-sm hover:border-slate-700 transition-all duration-200">
              <div className="text-3xl mb-4">🔧</div>
              <h3 className="text-lg font-semibold mb-2">Task-Specific</h3>
              <p className="text-slate-400">Tailored for your trades. Roofing, electrical, plumbing, excavation.</p>
            </div>

            <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6 backdrop-blur-sm hover:border-slate-700 transition-all duration-200">
              <div className="text-3xl mb-4">📊</div>
              <h3 className="text-lg font-semibold mb-2">Compliance Records</h3>
              <p className="text-slate-400">Automatic record keeping. SafeWork inspector ready.</p>
            </div>

            <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6 backdrop-blur-sm hover:border-slate-700 transition-all duration-200">
              <div className="text-3xl mb-4">🏗️</div>
              <h3 className="text-lg font-semibold mb-2">Multi-Site</h3>
              <p className="text-slate-400">Manage multiple sites from one dashboard. Scale across projects.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="py-16 sm:py-24">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center space-y-8">
            <h2 className="text-3xl sm:text-4xl font-bold">
              Trusted by Australian builders
            </h2>
            
            <div className="flex flex-wrap justify-center items-center gap-8 text-slate-400">
              <div className="flex items-center space-x-2">
                <span className="text-2xl">🇦🇺</span>
                <span>Built for Australian standards</span>
              </div>
              <div className="flex items-center space-x-2">
                <span className="text-2xl">⚖️</span>
                <span>SafeWork compliant</span>
              </div>
              <div className="flex items-center space-x-2">
                <span className="text-2xl">🏗️</span>
                <span>Construction industry focused</span>
              </div>
            </div>

            <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-8 backdrop-blur-sm max-w-2xl mx-auto">
              <blockquote className="text-xl text-slate-300 italic mb-4">
                "Finally, someone who gets it. Built by people who actually work on sites."
              </blockquote>
              <p className="text-slate-500">— Early access feedback</p>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-16 sm:py-24 bg-gradient-to-b from-slate-950 to-slate-900/50">
        <div className="max-w-4xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              Common questions
            </h2>
          </div>

          <div className="space-y-4">
            {[
              {
                q: "Is this actually compliant with SafeWork requirements?",
                a: "Absolutely. We've built SafeTalk specifically for Australian construction compliance. Every generated toolbox talk includes required elements: hazard identification, risk controls, and proper documentation. We stay updated with SafeWork regulations across all states."
              },
              {
                q: "What if the AI gets something wrong about my trade?",
                a: "You can review and edit every toolbox talk before your crew sees it. Plus, our AI is trained specifically on Australian construction practices and safety standards. But you're always in control of the final content."
              },
              {
                q: "How does the weather integration work?",
                a: "We pull live weather data for your site location and automatically include relevant warnings in your toolbox talk. High winds, extreme heat, rain, storms - if it affects safety, it's in your briefing."
              },
              {
                q: "Can I use this across multiple sites?",
                a: "Yes! Manage all your sites from one dashboard. Each site can have different trades, hazards, and settings. Perfect for builders managing multiple projects."
              },
              {
                q: "What about internet connectivity on remote sites?",
                a: "The QR code sign-off works offline. Signatures are stored locally and sync when connection returns. Your toolbox talks are also downloadable as PDFs for backup."
              }
            ].map((faq, index) => (
              <div key={index} className="bg-slate-900/50 border border-slate-800 rounded-xl backdrop-blur-sm overflow-hidden">
                <button
                  onClick={() => setOpenFaq(openFaq === index ? null : index)}
                  className="w-full px-6 py-4 text-left flex items-center justify-between hover:bg-slate-800/30 transition-colors duration-200"
                >
                  <span className="font-medium text-white">{faq.q}</span>
                  <span className={`text-slate-400 transition-transform duration-200 ${openFaq === index ? 'rotate-180' : ''}`}>
                    ▼
                  </span>
                </button>
                {openFaq === index && (
                  <div className="px-6 pb-4 text-slate-300 border-t border-slate-700/50">
                    <p className="pt-4">{faq.a}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="py-16 sm:py-24">
        <div className="max-w-4xl mx-auto px-4 text-center space-y-8">
          <div className="space-y-4">
            <h2 className="text-3xl sm:text-5xl font-bold">
              Ready to never write another
              <span className="block bg-gradient-to-r from-red-400 to-orange-400 bg-clip-text text-transparent">
                toolbox talk again?
              </span>
            </h2>
            <p className="text-xl text-slate-400 max-w-2xl mx-auto">
              Join 1,200+ Australian builders getting early access. 
              Limited spots available for March launch.
            </p>
          </div>

          <WaitlistForm showUrgency={true} />

          <p className="text-sm text-slate-500">
            No spam. Just updates on launch progress and early access invites.
          </p>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-slate-800 py-8">
        <div className="max-w-6xl mx-auto px-4 text-center">
          <p className="text-slate-400">
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