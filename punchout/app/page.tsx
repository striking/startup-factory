'use client'

import { useState } from 'react'
import { Geist } from 'next/font/google'
import { Analytics } from '@vercel/analytics/react'

const geist = Geist({ subsets: ['latin'] })

export default function Page() {
  // removed fake counter
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
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email,
          name,
          product: 'punchout'
        })
      })
      
      // form submitted
      setIsSubmitted(true)
      setEmail('')
      setName('')
    } catch (error) {
      console.error('Error submitting to waitlist:', error)
    } finally {
      setIsSubmitting(false)
    }
  }

  const toggleFaq = (index: number) => {
    setOpenFaq(openFaq === index ? null : index)
  }

  return (
    <div className={`min-h-screen bg-slate-950 text-white ${geist.className}`}>
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-blue-500/10 via-transparent to-purple-500/10"></div>
        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-20 pb-32">
          <div className="text-center">
            <div className="inline-flex items-center gap-2 bg-white/5 backdrop-blur-sm border border-white/10 rounded-full px-4 py-2 mb-8">
              <span className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
              <span className="text-sm text-gray-300">Now in beta</span>
            </div>
            
            <h1 className="text-5xl sm:text-7xl font-bold mb-6 bg-gradient-to-r from-white via-blue-100 to-blue-200 bg-clip-text text-transparent">
              PunchOut
            </h1>
            
            <p className="text-xl sm:text-2xl text-gray-300 mb-4 max-w-3xl mx-auto">
              Defects found. Defects fixed. Done.
            </p>
            
            <p className="text-lg text-gray-400 mb-12 max-w-2xl mx-auto">
              The defect management app that Australian builders actually want to use. 
              No more lost lists, confused subbies, or client disputes.
            </p>

            {/* Waitlist Form */}
            <div className="max-w-md mx-auto">
              {isSubmitted ? (
                <div className="bg-green-500/10 backdrop-blur-sm border border-green-500/20 rounded-2xl p-6 mb-8">
                  <div className="text-green-400 text-lg font-semibold mb-2">You're on the list! 🎉</div>
                  <p className="text-gray-300 text-sm">We'll let you know when PunchOut is ready.</p>
                </div>
              ) : (
                <form onSubmit={handleSubmit} className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-6 mb-8">
                  <div className="space-y-4">
                    <input
                      type="text"
                      placeholder="Your name"
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                      className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                      required
                    />
                    <input
                      type="email"
                      placeholder="your.email@company.com.au"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                      required
                    />
                    <button
                      type="submit"
                      disabled={isSubmitting}
                      className="w-full bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700 text-white font-semibold py-3 px-6 rounded-xl transition-all duration-200 transform hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      {isSubmitting ? 'Joining...' : 'Join the Waitlist'}
                    </button>
                  </div>
                </form>
              )}
              
              <div className="text-center text-gray-400">
                <span className="text-2xl font-bold text-blue-400">Early access</span> now open
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Problem Section */}
      <section className="py-24 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Sound familiar?</h2>
            <p className="text-xl text-gray-400">Every builder knows these pain points</p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-8 hover:bg-white/10 transition-all duration-300">
              <div className="text-4xl mb-4">📝</div>
              <h3 className="text-xl font-semibold mb-4 text-red-400">The Lost List</h3>
              <p className="text-gray-300 italic">
                "Walk-through with client. 40 defects on back of plan. Lost half by Tuesday."
              </p>
            </div>
            
            <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-8 hover:bg-white/10 transition-all duration-300">
              <div className="text-4xl mb-4">📱</div>
              <h3 className="text-xl font-semibold mb-4 text-red-400">The Text Mess</h3>
              <p className="text-gray-300 italic">
                "Three subbies to chase. None know their items. List buried in texts."
              </p>
            </div>
            
            <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-8 hover:bg-white/10 transition-all duration-300">
              <div className="text-4xl mb-4">🤝</div>
              <h3 className="text-xl font-semibold mb-4 text-red-400">The Scope Creep</h3>
              <p className="text-gray-300 italic">
                "Client adding things 6 months after handover. No record of what was agreed."
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Show Don't Tell Section */}
      <section className="py-24 px-4 sm:px-6 lg:px-8 bg-gradient-to-b from-transparent to-blue-500/5">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">From chaos to clarity</h2>
            <p className="text-xl text-gray-400">See the difference PunchOut makes</p>
          </div>
          
          <div className="grid lg:grid-cols-2 gap-12 items-center">
            {/* Before */}
            <div className="text-center">
              <h3 className="text-2xl font-semibold mb-8 text-red-400">Before: The old way</h3>
              <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-8 relative">
                <svg viewBox="0 0 300 400" className="w-full max-w-sm mx-auto">
                  {/* Crumpled paper background */}
                  <rect width="300" height="400" fill="#f8f9fa" rx="8"/>
                  <path d="M50 50 L250 50 L250 350 L50 350 Z" fill="#ffffff" stroke="#ddd" strokeWidth="2"/>
                  
                  {/* Coffee stain */}
                  <circle cx="200" cy="100" r="25" fill="#8B4513" opacity="0.3"/>
                  <circle cx="205" cy="95" r="15" fill="#8B4513" opacity="0.5"/>
                  
                  {/* Scribbled annotations */}
                  <path d="M70 80 Q80 85 90 80 Q100 75 110 80" stroke="#000" strokeWidth="2" fill="none"/>
                  <text x="70" y="100" fontSize="8" fill="#000">Kitchen tap leaking</text>
                  
                  <path d="M70 130 L120 130" stroke="#000" strokeWidth="2"/>
                  <text x="70" y="150" fontSize="8" fill="#000">Door won't close</text>
                  
                  {/* Illegible scribbles */}
                  <path d="M70 180 Q75 185 80 180 Q85 175 90 180 Q95 185 100 180" stroke="#000" strokeWidth="1" fill="none"/>
                  <path d="M70 200 Q80 205 90 200 Q100 195 110 200" stroke="#000" strokeWidth="1" fill="none"/>
                  
                  {/* Arrows pointing everywhere */}
                  <path d="M150 120 L180 150" stroke="#ff0000" strokeWidth="2" markerEnd="url(#arrowhead)"/>
                  <path d="M120 200 L160 180" stroke="#ff0000" strokeWidth="2" markerEnd="url(#arrowhead)"/>
                  
                  <defs>
                    <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
                      <polygon points="0 0, 10 3.5, 0 7" fill="#ff0000"/>
                    </marker>
                  </defs>
                  
                  {/* Crease lines */}
                  <path d="M0 200 L300 200" stroke="#ccc" strokeWidth="1" opacity="0.5"/>
                  <path d="M150 0 L150 400" stroke="#ccc" strokeWidth="1" opacity="0.5"/>
                </svg>
                <p className="text-gray-400 mt-4 text-sm">Crumpled plans, lost notes, confused trades</p>
              </div>
            </div>
            
            {/* After */}
            <div className="text-center">
              <h3 className="text-2xl font-semibold mb-8 text-green-400">After: PunchOut</h3>
              <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-8">
                <div className="bg-gray-900 rounded-2xl p-4 max-w-sm mx-auto">
                  {/* Mobile app mockup */}
                  <div className="bg-white rounded-xl p-4">
                    <div className="flex justify-between items-center mb-4">
                      <h4 className="text-gray-800 font-semibold text-sm">Site Plan</h4>
                      <div className="text-xs text-gray-600">12/18 resolved — 67%</div>
                    </div>
                    
                    <svg viewBox="0 0 250 200" className="w-full">
                      {/* Clean floor plan */}
                      <rect width="250" height="200" fill="#f8f9fa" rx="4"/>
                      <rect x="20" y="20" width="210" height="160" fill="#ffffff" stroke="#e9ecef" strokeWidth="1"/>
                      
                      {/* Rooms */}
                      <rect x="30" y="30" width="80" height="60" fill="none" stroke="#dee2e6" strokeWidth="1"/>
                      <text x="70" y="65" fontSize="10" fill="#6c757d" textAnchor="middle">Kitchen</text>
                      
                      <rect x="120" y="30" width="100" height="60" fill="none" stroke="#dee2e6" strokeWidth="1"/>
                      <text x="170" y="65" fontSize="10" fill="#6c757d" textAnchor="middle">Living</text>
                      
                      <rect x="30" y="100" width="190" height="70" fill="none" stroke="#dee2e6" strokeWidth="1"/>
                      <text x="125" y="140" fontSize="10" fill="#6c757d" textAnchor="middle">Bedroom</text>
                      
                      {/* Colour-coded pins */}
                      <circle cx="60" cy="50" r="6" fill="#dc3545"/>
                      <text x="60" y="55" fontSize="8" fill="white" textAnchor="middle">1</text>
                      
                      <circle cx="90" cy="70" r="6" fill="#ffc107"/>
                      <text x="90" y="75" fontSize="8" fill="black" textAnchor="middle">2</text>
                      
                      <circle cx="150" cy="45" r="6" fill="#28a745"/>
                      <text x="150" y="50" fontSize="8" fill="white" textAnchor="middle">3</text>
                      
                      <circle cx="180" cy="60" r="6" fill="#28a745"/>
                      <text x="180" y="65" fontSize="8" fill="white" textAnchor="middle">4</text>
                      
                      <circle cx="80" cy="130" r="6" fill="#ffc107"/>
                      <text x="80" y="135" fontSize="8" fill="black" textAnchor="middle">5</text>
                    </svg>
                    
                    {/* Legend */}
                    <div className="flex justify-center gap-4 mt-4 text-xs">
                      <div className="flex items-center gap-1">
                        <div className="w-3 h-3 bg-red-500 rounded-full"></div>
                        <span className="text-gray-600">New</span>
                      </div>
                      <div className="flex items-center gap-1">
                        <div className="w-3 h-3 bg-yellow-500 rounded-full"></div>
                        <span className="text-gray-600">Assigned</span>
                      </div>
                      <div className="flex items-center gap-1">
                        <div className="w-3 h-3 bg-green-500 rounded-full"></div>
                        <span className="text-gray-600">Fixed</span>
                      </div>
                    </div>
                  </div>
                </div>
                <p className="text-gray-400 mt-4 text-sm">Clean plans, clear status, happy trades</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works Section */}
      <section className="py-24 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">How it works</h2>
            <p className="text-xl text-gray-400">Three simple steps to defect-free handovers</p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-r from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mb-6 mx-auto">
                1
              </div>
              <h3 className="text-xl font-semibold mb-4">Walk, Snap & Pin</h3>
              <p className="text-gray-400">
                Walk the site, snap photos of defects, and pin them to your floor plan. 
                Add descriptions and priority levels on the spot.
              </p>
            </div>
            
            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-r from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mb-6 mx-auto">
                2
              </div>
              <h3 className="text-xl font-semibold mb-4">Assign with One Tap</h3>
              <p className="text-gray-400">
                Tap a defect, select the trade, and they get instant notification with 
                photo, location, and deadline. No more phone tag.
              </p>
            </div>
            
            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-r from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mb-6 mx-auto">
                3
              </div>
              <h3 className="text-xl font-semibold mb-4">Track & Sign Off</h3>
              <p className="text-gray-400">
                Watch fixes happen in real-time. Client signs off digitally. 
                Everything's documented for warranty claims.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="py-24 px-4 sm:px-6 lg:px-8 bg-gradient-to-b from-blue-500/5 to-transparent">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Everything you need</h2>
            <p className="text-xl text-gray-400">Built for Australian building sites</p>
          </div>
          
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-6 hover:bg-white/10 transition-all duration-300">
              <div className="text-3xl mb-4">🚶‍♂️</div>
              <h3 className="text-lg font-semibold mb-2">Walk & Log</h3>
              <p className="text-gray-400 text-sm">
                Capture defects on-site with photos, voice notes, and GPS location. 
                Works offline too.
              </p>
            </div>
            
            <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-6 hover:bg-white/10 transition-all duration-300">
              <div className="text-3xl mb-4">📍</div>
              <h3 className="text-lg font-semibold mb-2">Floor Plan Pins</h3>
              <p className="text-gray-400 text-sm">
                Upload your plans and pin defects exactly where they are. 
                Visual clarity for everyone.
              </p>
            </div>
            
            <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-6 hover:bg-white/10 transition-all duration-300">
              <div className="text-3xl mb-4">👷‍♂️</div>
              <h3 className="text-lg font-semibold mb-2">Subbie Assignment</h3>
              <p className="text-gray-400 text-sm">
                One tap to assign defects to trades. They get notifications with 
                all the details they need.
              </p>
            </div>
            
            <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-6 hover:bg-white/10 transition-all duration-300">
              <div className="text-3xl mb-4">📸</div>
              <h3 className="text-lg font-semibold mb-2">Photo Proof</h3>
              <p className="text-gray-400 text-sm">
                Before and after photos with timestamps. Perfect for progress 
                tracking and disputes.
              </p>
            </div>
            
            <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-6 hover:bg-white/10 transition-all duration-300">
              <div className="text-3xl mb-4">✅</div>
              <h3 className="text-lg font-semibold mb-2">Client Sign-Off</h3>
              <p className="text-gray-400 text-sm">
                Digital signatures on completed work. Clear approval trail 
                for handover and warranty.
              </p>
            </div>
            
            <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-6 hover:bg-white/10 transition-all duration-300">
              <div className="text-3xl mb-4">🛡️</div>
              <h3 className="text-lg font-semibold mb-2">Warranty Tracker</h3>
              <p className="text-gray-400 text-sm">
                Automatic warranty periods and reminders. Never miss a 
                warranty claim again.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Social Proof Section */}
      <section className="py-24 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Builders love PunchOut</h2>
            <p className="text-xl text-gray-400">Early feedback from our beta users</p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-6">
              <div className="flex items-center mb-4">
                <div className="w-12 h-12 bg-gradient-to-r from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-white font-bold mr-4">
                  M
                </div>
                <div>
                  <div className="font-semibold">Mike Chen</div>
                  <div className="text-sm text-gray-400">Project Manager, Sydney</div>
                </div>
              </div>
              <p className="text-gray-300 italic">
                "Finally, an app that gets how we actually work on site. 
                No more lost defect lists or confused subbies."
              </p>
            </div>
            
            <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-6">
              <div className="flex items-center mb-4">
                <div className="w-12 h-12 bg-gradient-to-r from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-white font-bold mr-4">
                  S
                </div>
                <div>
                  <div className="font-semibold">Sarah Williams</div>
                  <div className="text-sm text-gray-400">Builder, Melbourne</div>
                </div>
              </div>
              <p className="text-gray-300 italic">
                "Cut our defect resolution time in half. Clients are happier, 
                subbies know what to do, and I sleep better."
              </p>
            </div>
            
            <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-6">
              <div className="flex items-center mb-4">
                <div className="w-12 h-12 bg-gradient-to-r from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-white font-bold mr-4">
                  D
                </div>
                <div>
                  <div className="font-semibold">Dave Thompson</div>
                  <div className="text-sm text-gray-400">Site Supervisor, Brisbane</div>
                </div>
              </div>
              <p className="text-gray-300 italic">
                "The floor plan pins are brilliant. Everyone knows exactly 
                where the problem is. No more 'near the kitchen' descriptions."
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ Section */}
      <section className="py-24 px-4 sm:px-6 lg:px-8 bg-gradient-to-b from-transparent to-blue-500/5">
        <div className="max-w-4xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Common questions</h2>
            <p className="text-xl text-gray-400">Everything you need to know about PunchOut</p>
          </div>
          
          <div className="space-y-4">
            {[
              {
                question: "How does PunchOut work offline?",
                answer: "PunchOut stores everything locally on your device when you're offline. Photos, notes, and pins sync automatically when you're back online. Perfect for sites with patchy reception."
              },
              {
                question: "Can I use my existing floor plans?",
                answer: "Absolutely. Upload PDFs, JPEGs, or even photos of hand-drawn plans. PunchOut works with whatever plans you've got."
              },
              {
                question: "How do subbies get notified?",
                answer: "They get SMS and email notifications with a link to view their assigned defects. No app download required for them - they can view everything in their browser."
              },
              {
                question: "What about client sign-offs?",
                answer: "Clients can sign off on completed work digitally using their phone or tablet. Creates a clear audit trail for handover and warranty purposes."
              },
              {
                question: "Is my data secure?",
                answer: "Your data is encrypted and stored on Australian servers. We're fully compliant with Australian privacy laws and never share your information."
              },
              {
                question: "How much will it cost?",
                answer: "We're still finalising pricing, but it'll be affordable for builders of all sizes. Think less than your monthly coffee budget per project."
              }
            ].map((faq, index) => (
              <div key={index} className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl overflow-hidden">
                <button
                  onClick={() => toggleFaq(index)}
                  className="w-full px-6 py-4 text-left flex justify-between items-center hover:bg-white/5 transition-all duration-200"
                >
                  <span className="font-semibold">{faq.question}</span>
                  <span className={`transform transition-transform duration-200 ${openFaq === index ? 'rotate-180' : ''}`}>
                    ↓
                  </span>
                </button>
                {openFaq === index && (
                  <div className="px-6 pb-4">
                    <p className="text-gray-400">{faq.answer}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA Section */}
      <section className="py-24 px-4 sm:px-6 lg:px-8">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-3xl sm:text-4xl font-bold mb-6">
            Ready to fix defects the smart way?
          </h2>
          <p className="text-xl text-gray-400 mb-12">
            Request early access. Limited spots available. 
            Be the first to know when PunchOut launches.
          </p>
          
          <div className="max-w-md mx-auto">
            {isSubmitted ? (
              <div className="bg-green-500/10 backdrop-blur-sm border border-green-500/20 rounded-2xl p-8">
                <div className="text-green-400 text-2xl font-semibold mb-4">You're all set! 🚀</div>
                <p className="text-gray-300">
                  We'll send you early access as soon as PunchOut is ready. 
                  Thanks for joining the revolution!
                </p>
              </div>
            ) : (
              <form onSubmit={handleSubmit} className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-2xl p-8">
                <div className="space-y-4">
                  <input
                    type="text"
                    placeholder="Your name"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                    required
                  />
                  <input
                    type="email"
                    placeholder="your.email@company.com.au"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                    required
                  />
                  <button
                    type="submit"
                    disabled={isSubmitting}
                    className="w-full bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700 text-white font-semibold py-4 px-6 rounded-xl transition-all duration-200 transform hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed text-lg"
                  >
                    {isSubmitting ? 'Joining...' : 'Get Early Access'}
                  </button>
                </div>
              </form>
            )}
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-white/10 py-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto text-center">
          <p className="text-gray-400">
            Built with ❤️ by{' '}
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