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
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email,
          product: 'texttime',
          referrer: document.referrer || '',
          utmSource: urlParams.get('utm_source') || '',
          utmMedium: urlParams.get('utm_medium') || '',
          utmCampaign: urlParams.get('utm_campaign') || ''
        })
      })
      setIsSubmitted(true)
    } catch (error) {
      console.error('Error:', error)
    } finally {
      setIsSubmitting(false)
    }
  }

  const WaitlistForm = ({ showUrgency = false }: { showUrgency?: boolean }) => (
    <div className="w-full max-w-md mx-auto">
      {isSubmitted ? (
        <div className="text-center p-6 bg-slate-900/50 backdrop-blur-sm rounded-2xl border border-slate-800">
          <div className="text-2xl mb-2">🎉</div>
          <h3 className="text-lg font-semibold text-white mb-2">You're on the list!</h3>
          <p className="text-slate-400">We'll send you early access when it's ready.</p>
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="flex flex-col sm:flex-row gap-3">
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="Enter your email"
              required
              className="flex-1 px-4 py-3 bg-slate-900/50 backdrop-blur-sm border border-slate-700 rounded-xl text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
            />
            <button
              type="submit"
              disabled={isSubmitting}
              className="px-6 py-3 bg-gradient-to-r from-blue-600 to-blue-500 text-white font-semibold rounded-xl hover:from-blue-500 hover:to-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:ring-offset-slate-950 transition-all transform hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isSubmitting ? 'Joining...' : 'Request Early Access'}
            </button>
          </div>
          {showUrgency && (
            <p className="text-sm text-slate-400 text-center">
              ⚡ Limited spots available for beta testing
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
        <div className="absolute inset-0 bg-gradient-to-br from-blue-600/10 via-transparent to-purple-600/10"></div>
        <div className="relative max-w-6xl mx-auto px-4 py-20 sm:py-32">
          <div className="text-center space-y-8">
            <div className="inline-flex items-center gap-2 px-4 py-2 bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-full text-sm text-slate-300">
              <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
              Invitation Only Beta
            </div>
            
            <h1 className="text-4xl sm:text-6xl lg:text-7xl font-bold tracking-tight">
              Never miss a{' '}
              <span className="bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">
                customer message
              </span>{' '}
              again
            </h1>
            
            <p className="text-xl sm:text-2xl text-slate-400 max-w-3xl mx-auto leading-relaxed">
              AI-powered SMS and call handling for Australian tradies. Book jobs while you're under the house, up a ladder, or off the tools.
            </p>
            
            <WaitlistForm />
            
            <div className="flex items-center justify-center gap-6 text-sm text-slate-500">
              <div className="flex items-center gap-2">
                <div className="w-2 h-2 bg-blue-500 rounded-full"></div>
                <span>Early access open</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-2 h-2 bg-green-500 rounded-full"></div>
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
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Sound familiar?</h2>
            <p className="text-xl text-slate-400">Every tradie knows these pain points</p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-8 hover:border-slate-700 transition-all">
              <div className="text-4xl mb-4">📱</div>
              <blockquote className="text-lg text-slate-300 italic mb-4">
                "Phone rings while you're under a house. By the time you call back, they've booked someone else."
              </blockquote>
              <cite className="text-sm text-slate-500">— Dave, Plumber, Brisbane</cite>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-8 hover:border-slate-700 transition-all">
              <div className="text-4xl mb-4">🔥</div>
              <blockquote className="text-lg text-slate-300 italic mb-4">
                "6 missed calls and 4 unread texts by 3pm. Half are new leads. Good luck figuring out which."
              </blockquote>
              <cite className="text-sm text-slate-500">— Sarah, Electrician, Melbourne</cite>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-8 hover:border-slate-700 transition-all">
              <div className="text-4xl mb-4">💸</div>
              <blockquote className="text-lg text-slate-300 italic mb-4">
                "Hired a receptionist for $50K/year. She calls in sick every second Friday."
              </blockquote>
              <cite className="text-sm text-slate-500">— Mike, Builder, Sydney</cite>
            </div>
          </div>
        </div>
      </section>

      {/* Show Don't Tell Section */}
      <section className="py-20 px-4 bg-gradient-to-b from-transparent to-slate-900/30">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">See the difference</h2>
            <p className="text-xl text-slate-400">Your phone becomes your best employee</p>
          </div>
          
          <div className="grid lg:grid-cols-2 gap-12 items-center">
            {/* Without TextTime */}
            <div className="space-y-6">
              <div className="text-center">
                <h3 className="text-2xl font-semibold text-red-400 mb-2">Without TextTime</h3>
                <p className="text-slate-400">Chaos. Missed opportunities.</p>
              </div>
              
              <div className="bg-slate-900 rounded-3xl p-6 max-w-sm mx-auto border border-slate-800">
                {/* Phone mockup */}
                <div className="bg-black rounded-2xl p-4 space-y-4">
                  <div className="flex justify-between items-center text-white text-sm">
                    <span>9:47</span>
                    <div className="flex gap-1">
                      <div className="w-4 h-2 bg-white rounded-sm"></div>
                      <div className="w-4 h-2 bg-white rounded-sm"></div>
                      <div className="w-4 h-2 bg-white rounded-sm"></div>
                    </div>
                  </div>
                  
                  {/* Missed calls */}
                  <div className="space-y-2">
                    <div className="flex items-center justify-between bg-red-900/30 rounded-lg p-3">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 bg-red-500 rounded-full flex items-center justify-center text-white text-xs font-bold">5</div>
                        <div>
                          <div className="text-white text-sm font-medium">Missed Calls</div>
                          <div className="text-red-400 text-xs">Unknown numbers</div>
                        </div>
                      </div>
                    </div>
                    
                    <div className="flex items-center justify-between bg-red-900/30 rounded-lg p-3">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 bg-red-500 rounded-full flex items-center justify-center text-white text-xs font-bold">3</div>
                        <div>
                          <div className="text-white text-sm font-medium">Unread Messages</div>
                          <div className="text-red-400 text-xs">Could be leads...</div>
                        </div>
                      </div>
                    </div>
                    
                    <div className="flex items-center justify-between bg-red-900/30 rounded-lg p-3">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 bg-red-500 rounded-full flex items-center justify-center text-white text-xs">📧</div>
                        <div>
                          <div className="text-white text-sm font-medium">Voicemail</div>
                          <div className="text-red-400 text-xs">2 new messages</div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            
            {/* With TextTime */}
            <div className="space-y-6">
              <div className="text-center">
                <h3 className="text-2xl font-semibold text-green-400 mb-2">With TextTime</h3>
                <p className="text-slate-400">AI handles it all. You keep working.</p>
              </div>
              
              <div className="bg-slate-900 rounded-3xl p-6 max-w-sm mx-auto border border-slate-800">
                {/* Phone mockup with messages */}
                <div className="bg-black rounded-2xl p-4 space-y-4">
                  <div className="flex justify-between items-center text-white text-sm">
                    <span>9:47</span>
                    <div className="flex gap-1">
                      <div className="w-4 h-2 bg-white rounded-sm"></div>
                      <div className="w-4 h-2 bg-white rounded-sm"></div>
                      <div className="w-4 h-2 bg-white rounded-sm"></div>
                    </div>
                  </div>
                  
                  {/* Message conversation */}
                  <div className="space-y-3 text-sm">
                    <div className="text-center text-xs text-slate-500">Today 2:15 PM</div>
                    
                    <div className="bg-slate-700 rounded-2xl rounded-bl-md p-3 max-w-[80%]">
                      <div className="text-white">Hi, need a plumber for blocked drain. Available today?</div>
                    </div>
                    
                    <div className="bg-blue-600 rounded-2xl rounded-br-md p-3 max-w-[80%] ml-auto">
                      <div className="text-white">Hi! Yes, I can help with that. I have availability at 4:30 PM today. The callout is $120 + parts. What's your address?</div>
                    </div>
                    
                    <div className="bg-slate-700 rounded-2xl rounded-bl-md p-3 max-w-[80%]">
                      <div className="text-white">Perfect! 15 Smith St, Newtown. See you at 4:30</div>
                    </div>
                    
                    <div className="bg-blue-600 rounded-2xl rounded-br-md p-3 max-w-[80%] ml-auto">
                      <div className="text-white">Booked! I'll text you when I'm 10 mins away. Thanks!</div>
                    </div>
                    
                    <div className="text-center text-xs text-green-400">✓ Job booked automatically</div>
                  </div>
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
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">How it works</h2>
            <p className="text-xl text-slate-400">Three steps to never miss a lead again</p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            <div className="text-center space-y-4">
              <div className="w-16 h-16 bg-gradient-to-br from-blue-500 to-blue-600 rounded-2xl flex items-center justify-center text-2xl font-bold mx-auto">1</div>
              <h3 className="text-xl font-semibold">Customer texts or calls</h3>
              <p className="text-slate-400">Your number stays the same. Customers reach out like normal.</p>
            </div>
            
            <div className="text-center space-y-4">
              <div className="w-16 h-16 bg-gradient-to-br from-blue-500 to-blue-600 rounded-2xl flex items-center justify-center text-2xl font-bold mx-auto">2</div>
              <h3 className="text-xl font-semibold">AI responds instantly</h3>
              <p className="text-slate-400">Smart replies handle quotes, bookings, and common questions automatically.</p>
            </div>
            
            <div className="text-center space-y-4">
              <div className="w-16 h-16 bg-gradient-to-br from-blue-500 to-blue-600 rounded-2xl flex items-center justify-center text-2xl font-bold mx-auto">3</div>
              <h3 className="text-xl font-semibold">Jobs get booked</h3>
              <p className="text-slate-400">While you work, your calendar fills up. Check your dashboard later.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-20 px-4 bg-gradient-to-b from-transparent to-slate-900/30">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Everything you need</h2>
            <p className="text-xl text-slate-400">Built specifically for Australian tradies</p>
          </div>
          
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-6 hover:border-slate-700 transition-all">
              <div className="text-3xl mb-4">💬</div>
              <h3 className="text-lg font-semibold mb-2">Auto-Reply SMS</h3>
              <p className="text-slate-400">Instant responses to common questions. Sounds like you wrote it.</p>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-6 hover:border-slate-700 transition-all">
              <div className="text-3xl mb-4">📞</div>
              <h3 className="text-lg font-semibold mb-2">Smart Call Handling</h3>
              <p className="text-slate-400">AI answers calls when you can't. Takes messages and books appointments.</p>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-6 hover:border-slate-700 transition-all">
              <div className="text-3xl mb-4">🌙</div>
              <h3 className="text-lg font-semibold mb-2">After-Hours Coverage</h3>
              <p className="text-slate-400">Capture leads while you sleep. Emergency calls get through.</p>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-6 hover:border-slate-700 transition-all">
              <div className="text-3xl mb-4">🎯</div>
              <h3 className="text-lg font-semibold mb-2">Lead Qualification</h3>
              <p className="text-slate-400">AI asks the right questions. You only get serious enquiries.</p>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-6 hover:border-slate-700 transition-all">
              <div className="text-3xl mb-4">📅</div>
              <h3 className="text-lg font-semibold mb-2">Booking Integration</h3>
              <p className="text-slate-400">Syncs with your calendar. No double bookings, no missed appointments.</p>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-6 hover:border-slate-700 transition-all">
              <div className="text-3xl mb-4">📊</div>
              <h3 className="text-lg font-semibold mb-2">Message Dashboard</h3>
              <p className="text-slate-400">See all conversations in one place. Take over anytime.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="py-20 px-4">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-3xl sm:text-4xl font-bold mb-8">Built for Australian tradies</h2>
          
          <div className="grid md:grid-cols-3 gap-8 mb-12">
            <div className="space-y-2">
              <div className="text-3xl font-bold text-blue-400">🇦🇺</div>
              <div className="text-lg font-semibold">Australian English</div>
              <div className="text-slate-400">Speaks like your customers do</div>
            </div>
            
            <div className="space-y-2">
              <div className="text-3xl font-bold text-blue-400">⚡</div>
              <div className="text-lg font-semibold">Industry Knowledge</div>
              <div className="text-slate-400">Understands trade terminology</div>
            </div>
            
            <div className="space-y-2">
              <div className="text-3xl font-bold text-blue-400">🔒</div>
              <div className="text-lg font-semibold">Privacy First</div>
              <div className="text-slate-400">Your data stays in Australia</div>
            </div>
          </div>
          
          <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-8">
            <p className="text-lg text-slate-300 italic mb-4">
              "Finally, someone who gets it. Built by tradies, for tradies. No Silicon Valley nonsense."
            </p>
            <div className="flex items-center justify-center gap-4">
              <div className="w-12 h-12 bg-gradient-to-br from-blue-500 to-purple-500 rounded-full flex items-center justify-center text-white font-bold">
                LS
              </div>
              <div className="text-left">
                <div className="font-semibold">Leva Solutions</div>
                <div className="text-sm text-slate-400">Australian Construction Tech</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-20 px-4 bg-gradient-to-b from-transparent to-slate-900/30">
        <div className="max-w-4xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Common questions</h2>
            <p className="text-xl text-slate-400">Everything you need to know</p>
          </div>
          
          <div className="space-y-4">
            {[
              {
                q: "Do I need to change my phone number?",
                a: "Nope. Keep your existing number. TextTime works behind the scenes with your current setup."
              },
              {
                q: "What if the AI gets something wrong?",
                a: "You're always in control. Check the dashboard, jump into any conversation, or set the AI to ask you before booking."
              },
              {
                q: "How much does it cost?",
                a: "We're still finalising pricing for the Australian market. Beta testers get special early-bird rates."
              },
              {
                q: "Will customers know it's AI?",
                a: "Only if you want them to. The AI is trained to sound natural and professional - like a good receptionist."
              },
              {
                q: "What about emergency calls?",
                a: "Emergency keywords (burst pipe, no power, etc.) always get through to you immediately. Safety first."
              }
            ].map((faq, index) => (
              <div key={index} className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl overflow-hidden">
                <button
                  onClick={() => setOpenFaq(openFaq === index ? null : index)}
                  className="w-full px-6 py-4 text-left flex items-center justify-between hover:bg-slate-800/50 transition-all"
                >
                  <span className="font-semibold">{faq.q}</span>
                  <span className={`transform transition-transform ${openFaq === index ? 'rotate-180' : ''}`}>
                    ↓
                  </span>
                </button>
                {openFaq === index && (
                  <div className="px-6 pb-4 text-slate-400">
                    {faq.a}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="py-20 px-4">
        <div className="max-w-4xl mx-auto text-center space-y-8">
          <h2 className="text-3xl sm:text-4xl font-bold">Ready to never miss a lead again?</h2>
          <p className="text-xl text-slate-400">
            Request early access. Limited spots available.
          </p>
          
          <WaitlistForm showUrgency={true} />
          
          <p className="text-sm text-slate-500">
            No spam. Unsubscribe anytime. Built with ❤️ for Australian tradies.
          </p>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-slate-800 py-8 px-4">
        <div className="max-w-6xl mx-auto text-center text-slate-500">
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