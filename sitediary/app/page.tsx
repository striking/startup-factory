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
    if (!email || isSubmitting) return

    setIsSubmitting(true)
    try {
      // Get UTM params from URL
      const urlParams = new URLSearchParams(window.location.search);

      await fetch(WAITLIST_API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email,
          product: 'sitediary',
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
    <div className="w-full max-w-md mx-auto">
      {isSubmitted ? (
        <div className="text-center p-6 bg-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700">
          <div className="text-2xl mb-2">✅</div>
          <p className="text-slate-300">You're on the list! We'll be in touch soon.</p>
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="flex flex-col sm:flex-row gap-3">
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="your.email@company.com.au"
              required
              className="flex-1 px-4 py-3 bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
            />
            <button
              type="submit"
              disabled={isSubmitting}
              className="px-6 py-3 bg-gradient-to-r from-blue-600 to-blue-500 text-white font-medium rounded-lg hover:from-blue-500 hover:to-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:ring-offset-slate-950 transition-all transform hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isSubmitting ? 'Joining...' : 'Request Early Access'}
            </button>
          </div>
          {showUrgency && (
            <p className="text-sm text-slate-400 text-center">
              Limited beta spots available. Request early access below.
            </p>
          )}
        </form>
      )}
    </div>
  )

  return (
    <div className={`min-h-screen bg-slate-950 text-white ${geist.className}`}>
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-blue-600/10 via-transparent to-slate-900/50"></div>
        <div className="relative max-w-6xl mx-auto px-4 py-20 sm:py-32">
          <div className="text-center space-y-8">
            <div className="inline-flex items-center px-4 py-2 bg-blue-500/10 backdrop-blur-sm border border-blue-500/20 rounded-full text-blue-300 text-sm font-medium">
              🚧 Invitation Only Beta
            </div>
            
            <h1 className="text-4xl sm:text-6xl lg:text-7xl font-bold tracking-tight">
              <span className="bg-gradient-to-r from-white via-slate-200 to-slate-400 bg-clip-text text-transparent">
                Site Diaries That
              </span>
              <br />
              <span className="bg-gradient-to-r from-blue-400 to-blue-600 bg-clip-text text-transparent">
                Write Themselves
              </span>
            </h1>
            
            <p className="text-xl sm:text-2xl text-slate-300 max-w-3xl mx-auto leading-relaxed">
              Record a 2-minute voice note. Get a compliance-ready site diary with weather data, personnel tracking, and proper formatting. Built for Australian construction.
            </p>
            
            <WaitlistForm />
            
            <div className="flex items-center justify-center gap-8 text-slate-400 text-sm">
              <div className="flex items-center gap-2">
                <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
                <span>Early access open</span>
              </div>
              <div className="flex items-center gap-2">
                <span>🇦🇺</span>
                <span>Australian weather data</span>
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
              Sound Familiar?
            </h2>
            <p className="text-xl text-slate-400">
              Every builder knows these daily frustrations
            </p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                emoji: "⏰",
                quote: "30 minutes every day writing a site diary nobody reads until there's a dispute."
              },
              {
                emoji: "🔍",
                quote: "Diary from last Tuesday says 'concreting'. Now I need to prove exactly what happened for a variation."
              },
              {
                emoji: "📱",
                quote: "Paper diaries get lost. Digital ones take longer than doing the work."
              }
            ].map((problem, index) => (
              <div key={index} className="bg-slate-800/30 backdrop-blur-sm border border-slate-700 rounded-xl p-8 hover:bg-slate-800/50 transition-all">
                <div className="text-4xl mb-4">{problem.emoji}</div>
                <blockquote className="text-lg text-slate-300 italic leading-relaxed">
                  "{problem.quote}"
                </blockquote>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Show Don't Tell Section */}
      <section className="py-20 px-4 bg-slate-900/50">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              See It In Action
            </h2>
            <p className="text-xl text-slate-400">
              From quick voice note to professional site diary in seconds
            </p>
          </div>
          
          <div className="grid lg:grid-cols-2 gap-12 items-center">
            {/* Before */}
            <div className="space-y-6">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 bg-red-500/20 rounded-full flex items-center justify-center text-red-400 font-bold">1</div>
                <h3 className="text-2xl font-semibold">Your Voice Note</h3>
              </div>
              
              <div className="bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-xl p-6">
                <div className="flex items-center gap-3 mb-4">
                  <div className="w-3 h-3 bg-red-500 rounded-full animate-pulse"></div>
                  <span className="text-sm text-slate-400">Recording • 1:47</span>
                </div>
                <div className="bg-slate-900/50 rounded-lg p-4 font-mono text-sm text-slate-300 leading-relaxed">
                  "Did the slab pour today, 3 trucks from Boral, started 7 finished about 2. Weather was crap morning but cleared. Plumber rough-in after lunch. Jake sick."
                </div>
                <div className="mt-4 flex items-center gap-2 text-xs text-slate-500">
                  <span>🎤</span>
                  <span>Quick and natural</span>
                </div>
              </div>
            </div>

            {/* After */}
            <div className="space-y-6">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 bg-green-500/20 rounded-full flex items-center justify-center text-green-400 font-bold">2</div>
                <h3 className="text-2xl font-semibold">Professional Diary</h3>
              </div>
              
              <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/30 backdrop-blur-sm border border-slate-600 rounded-xl p-6">
                <div className="space-y-4 text-sm">
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <span className="text-slate-400">Date:</span>
                      <span className="ml-2 text-white">Coming soon</span>
                    </div>
                    <div>
                      <span className="text-slate-400">Site:</span>
                      <span className="ml-2 text-white">Lot 47 Riverside</span>
                    </div>
                  </div>
                  
                  <div>
                    <span className="text-slate-400">Weather:</span>
                    <span className="ml-2 text-white">Rain clearing 14-22°C, SE 15km/h (BOM)</span>
                  </div>
                  
                  <div>
                    <span className="text-slate-400">Personnel:</span>
                    <span className="ml-2 text-white">Site crew (Jake absent - sick leave), Plumber (afternoon)</span>
                  </div>
                  
                  <div>
                    <span className="text-slate-400">Activities:</span>
                    <div className="ml-2 text-white mt-1">
                      • Concrete slab pour (07:00-14:00)
                      <br />
                      • Plumbing rough-in installation (13:00-17:00)
                    </div>
                  </div>
                  
                  <div>
                    <span className="text-slate-400">Materials:</span>
                    <span className="ml-2 text-white">Boral concrete - 3 truck deliveries</span>
                  </div>
                </div>
                
                <div className="mt-4 flex items-center gap-2 text-xs text-green-400">
                  <span>✅</span>
                  <span>Compliance ready</span>
                </div>
              </div>
            </div>
          </div>
          
          <div className="text-center mt-12">
            <div className="inline-flex items-center gap-2 px-4 py-2 bg-blue-500/10 backdrop-blur-sm border border-blue-500/20 rounded-full text-blue-300 text-sm">
              <span>⚡</span>
              <span>Automatic formatting, weather data, and compliance structure</span>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-20 px-4">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              How It Works
            </h2>
            <p className="text-xl text-slate-400">
              Three simple steps to professional site diaries
            </p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                step: "1",
                title: "Record",
                description: "Quick 2-minute voice note about your day. Natural speech, no structure needed.",
                icon: "🎤"
              },
              {
                step: "2",
                title: "AI Writes",
                description: "Our AI formats your notes, adds weather data, and structures everything for compliance.",
                icon: "🤖"
              },
              {
                step: "3",
                title: "Review & Share",
                description: "Quick review, approve, and share with your team or export for records.",
                icon: "✅"
              }
            ].map((step, index) => (
              <div key={index} className="text-center space-y-6">
                <div className="w-16 h-16 bg-gradient-to-br from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mx-auto">
                  {step.step}
                </div>
                <div className="text-4xl">{step.icon}</div>
                <h3 className="text-xl font-semibold">{step.title}</h3>
                <p className="text-slate-400 leading-relaxed">{step.description}</p>
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
              Everything You Need
            </h2>
            <p className="text-xl text-slate-400">
              Built specifically for Australian construction sites
            </p>
          </div>
          
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            {[
              {
                icon: "🎙️",
                title: "Voice-to-Diary",
                description: "Natural speech recognition optimised for construction terminology and Aussie accents."
              },
              {
                icon: "🌤️",
                title: "Auto Weather",
                description: "Automatic weather data from Bureau of Meteorology for accurate daily records."
              },
              {
                icon: "📸",
                title: "Photo Logging",
                description: "Attach photos with automatic timestamps and GPS coordinates for complete documentation."
              },
              {
                icon: "📋",
                title: "Compliance Format",
                description: "Industry-standard formatting that meets Australian construction compliance requirements."
              },
              {
                icon: "👥",
                title: "Team Entries",
                description: "Multiple team members can contribute to the same diary with proper attribution."
              },
              {
                icon: "📤",
                title: "Export Options",
                description: "PDF, Word, or CSV exports for easy sharing with clients, contractors, and authorities."
              }
            ].map((feature, index) => (
              <div key={index} className="bg-slate-800/30 backdrop-blur-sm border border-slate-700 rounded-xl p-6 hover:bg-slate-800/50 transition-all">
                <div className="text-3xl mb-4">{feature.icon}</div>
                <h3 className="text-lg font-semibold mb-3">{feature.title}</h3>
                <p className="text-slate-400 leading-relaxed">{feature.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="py-20 px-4">
        <div className="max-w-4xl mx-auto text-center">
          <div className="bg-gradient-to-r from-slate-800/50 to-slate-700/30 backdrop-blur-sm border border-slate-600 rounded-2xl p-12">
            <div className="text-4xl mb-6">🇦🇺</div>
            <h2 className="text-2xl sm:text-3xl font-bold mb-6">
              Built for Australian Construction
            </h2>
            <p className="text-lg text-slate-300 leading-relaxed mb-8">
              Developed with input from site supervisors, project managers, and builders across Australia. 
              Understands local terminology, weather patterns, and compliance requirements.
            </p>
            <div className="flex flex-wrap justify-center gap-4">
              {[
                "BOM Weather Integration",
                "Australian Standards",
                "Local Construction Terms",
                "Timezone Aware",
                "Privacy Compliant"
              ].map((badge, index) => (
                <span key={index} className="px-4 py-2 bg-blue-500/10 border border-blue-500/20 rounded-full text-blue-300 text-sm">
                  {badge}
                </span>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-20 px-4 bg-slate-900/30">
        <div className="max-w-4xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              Common Questions
            </h2>
            <p className="text-xl text-slate-400">
              Everything you need to know about SiteDiary
            </p>
          </div>
          
          <div className="space-y-4">
            {[
              {
                question: "How accurate is the voice recognition for construction terms?",
                answer: "Our AI is specifically trained on Australian construction terminology and accents. It understands industry-specific terms like 'formwork', 'DPC', 'screed', and common abbreviations used on site."
              },
              {
                question: "What happens to my voice recordings?",
                answer: "Voice recordings are processed securely and deleted immediately after transcription. Only the formatted text diary is stored. All data stays in Australia and complies with privacy regulations."
              },
              {
                question: "Can multiple people contribute to the same site diary?",
                answer: "Yes! Team members can add their own voice notes throughout the day. The AI combines all entries into a single, coherent diary with proper attribution for each contributor."
              },
              {
                question: "How does the weather data integration work?",
                answer: "We automatically pull weather data from the Bureau of Meteorology based on your site location. This includes temperature, conditions, wind speed, and any weather warnings relevant to construction work."
              },
              {
                question: "When will SiteDiary be available?",
                answer: "We're currently in private beta with selected builders. Public release is planned for Q2 2024. Join the waitlist to get early access and help shape the final product."
              }
            ].map((faq, index) => (
              <div key={index} className="bg-slate-800/30 backdrop-blur-sm border border-slate-700 rounded-xl overflow-hidden">
                <button
                  onClick={() => setOpenFaq(openFaq === index ? null : index)}
                  className="w-full px-6 py-4 text-left flex items-center justify-between hover:bg-slate-800/50 transition-all"
                >
                  <span className="font-medium text-lg">{faq.question}</span>
                  <span className={`transform transition-transform ${openFaq === index ? 'rotate-180' : ''}`}>
                    ↓
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
          <div className="bg-gradient-to-br from-blue-600/10 via-slate-800/50 to-slate-900/50 backdrop-blur-sm border border-slate-600 rounded-2xl p-12">
            <h2 className="text-3xl sm:text-4xl font-bold mb-6">
              Ready to Ditch the Daily Diary Grind?
            </h2>
            <p className="text-xl text-slate-300 mb-8 leading-relaxed">
              Request early access. Limited spots available.
            </p>
            <WaitlistForm showUrgency={true} />
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-12 px-4 border-t border-slate-800">
        <div className="max-w-6xl mx-auto text-center">
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