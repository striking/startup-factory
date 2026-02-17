import Link from 'next/link';
import { getAllSalaryGuides, getGuidesByState } from '@/lib/salary-guides';
import { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Electrician Salary Guide 2026 - Complete City-by-City Breakdown',
  description: 'Comprehensive electrician salary information for cities across America. Get accurate salary data, market insights, and career guidance for electrical professionals.',
  openGraph: {
    title: 'Electrician Salary Guide 2026 - Complete City-by-City Breakdown',
    description: 'Comprehensive electrician salary information for cities across America. Get accurate salary data, market insights, and career guidance for electrical professionals.',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Electrician Salary Guide 2026 - Complete City-by-City Breakdown',
    description: 'Comprehensive electrician salary information for cities across America. Get accurate salary data, market insights, and career guidance for electrical professionals.',
  },
};

export default function ElectricianSalaryIndexPage() {
  const guidesByState = getGuidesByState();
  const allGuides = getAllSalaryGuides();
  const totalCities = allGuides.length;

  // Calculate average salaries across all cities
  const avgApprentice = Math.round(
    allGuides.reduce((sum, guide) => sum + parseInt(guide.averageSalary.apprentice.replace(/[^0-9]/g, '')), 0) / totalCities
  );
  const avgJourneyman = Math.round(
    allGuides.reduce((sum, guide) => sum + parseInt(guide.averageSalary.journeyman.replace(/[^0-9]/g, '')), 0) / totalCities
  );

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Hero Section */}
      <div className="bg-blue-900 text-white py-16">
        <div className="container mx-auto px-4">
          <h1 className="text-4xl md:text-6xl font-bold mb-6">
            Electrician Salary Guide 2026
          </h1>
          <p className="text-xl md:text-2xl text-blue-200 mb-8">
            Comprehensive salary data, market insights, and career guidance for electrical professionals across America
          </p>
          <div className="grid md:grid-cols-3 gap-6">
            <div className="bg-blue-800 rounded-lg p-6">
              <div className="text-3xl font-bold">{totalCities}+</div>
              <div className="text-blue-200">Cities Covered</div>
            </div>
            <div className="bg-blue-800 rounded-lg p-6">
              <div className="text-3xl font-bold">${avgApprentice.toLocaleString()}</div>
              <div className="text-blue-200">Avg. Apprentice Salary</div>
            </div>
            <div className="bg-blue-800 rounded-lg p-6">
              <div className="text-3xl font-bold">${avgJourneyman.toLocaleString()}</div>
              <div className="text-blue-200">Avg. Journeyman Salary</div>
            </div>
          </div>
        </div>
      </div>

      <div className="container mx-auto px-4 py-12">
        {/* Introduction */}
        <div className="bg-white rounded-lg shadow-lg p-8 mb-12">
          <h2 className="text-3xl font-bold mb-6 text-gray-800">
            Why Choose Our Electrician Salary Guide?
          </h2>
          <div className="grid md:grid-cols-2 gap-8">
            <div>
              <ul className="space-y-4 text-gray-700">
                <li className="flex items-start">
                  <span className="text-blue-600 mr-3">✓</span>
                  <span>Accurate salary data from multiple industry sources</span>
                </li>
                <li className="flex items-start">
                  <span className="text-blue-600 mr-3">✓</span>
                  <span>Local market conditions and demand analysis</span>
                </li>
                <li className="flex items-start">
                  <span className="text-blue-600 mr-3">✓</span>
                  <span>Cost of living adjustments for each city</span>
                </li>
                <li className="flex items-start">
                  <span className="text-blue-600 mr-3">✓</span>
                  <span>Major employers and job opportunities</span>
                </li>
              </ul>
            </div>
            <div>
              <ul className="space-y-4 text-gray-700">
                <li className="flex items-start">
                  <span className="text-blue-600 mr-3">✓</span>
                  <span>Training and apprenticeship program information</span>
                </li>
                <li className="flex items-start">
                  <span className="text-blue-600 mr-3">✓</span>
                  <span>Union presence and collective bargaining rates</span>
                </li>
                <li className="flex items-start">
                  <span className="text-blue-600 mr-3">✓</span>
                  <span>State-specific licensing requirements</span>
                </li>
                <li className="flex items-start">
                  <span className="text-blue-600 mr-3">✓</span>
                  <span>Updated regularly with latest market data</span>
                </li>
              </ul>
            </div>
          </div>
        </div>

        {/* City Guides by State */}
        <div className="space-y-8">
          <h2 className="text-3xl font-bold text-gray-800 mb-6">
            Browse Salary Guides by State
          </h2>
          
          {Object.entries(guidesByState)
            .sort(([stateA], [stateB]) => stateA.localeCompare(stateB))
            .map(([state, guides]) => (
              <div key={state} className="bg-white rounded-lg shadow-lg p-6">
                <h3 className="text-2xl font-bold mb-4 text-gray-800 border-b pb-2">
                  {state}
                </h3>
                <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {guides
                    .sort((a, b) => a.city.localeCompare(b.city))
                    .map((guide) => (
                      <Link
                        key={guide.slug}
                        href={`/electrician-salary/${guide.slug}`}
                        className="block p-4 border border-gray-200 rounded-lg hover:border-blue-500 hover:shadow-md transition-all duration-200"
                      >
                        <div className="flex justify-between items-start mb-2">
                          <h4 className="font-semibold text-gray-800 hover:text-blue-600">
                            {guide.city}
                          </h4>
                          <span className={`text-xs px-2 py-1 rounded-full font-medium ${
                            guide.marketConditions.demand === 'Very High' ? 'bg-red-100 text-red-800' :
                            guide.marketConditions.demand === 'High' ? 'bg-orange-100 text-orange-800' :
                            guide.marketConditions.demand === 'Moderate' ? 'bg-yellow-100 text-yellow-800' :
                            'bg-gray-100 text-gray-800'
                          }`}>
                            {guide.marketConditions.demand}
                          </span>
                        </div>
                        <div className="text-sm text-gray-600 mb-2">
                          Journeyman: <span className="font-medium text-green-600">{guide.averageSalary.journeyman}</span>
                        </div>
                        <div className="text-xs text-gray-500">
                          {guide.description.substring(0, 100)}...
                        </div>
                      </Link>
                    ))}
                </div>
              </div>
            ))}
        </div>

        {/* Call to Action */}
        <div className="bg-blue-900 text-white rounded-lg p-8 mt-12 text-center">
          <h2 className="text-3xl font-bold mb-4">
            Ready to Advance Your Electrical Career?
          </h2>
          <p className="text-xl text-blue-200 mb-6">
            Get the tools and resources you need to succeed in the electrical industry
          </p>
          <Link
            href="/tools"
            className="inline-block bg-white text-blue-900 px-8 py-3 rounded-lg font-semibold hover:bg-gray-100 transition-colors duration-200"
          >
            Explore Our Tools
          </Link>
        </div>
      </div>
    </div>
  );
}