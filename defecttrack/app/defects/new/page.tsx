'use client';

import { useState, useEffect, type ChangeEvent, type FormEvent } from 'react';
import Link from 'next/link';
import type { DefectCategory, SeverityRating } from '../types';
import { saveDefect } from '../storage';

const CATEGORIES = [
  'structural',
  'waterproofing',
  'electrical',
  'plumbing',
  'fire safety',
  'cosmetic',
] as const;

const SEVERITY_LEVELS: SeverityRating[] = [1, 2, 3, 4, 5];

export default function NewDefectPage() {
  const [category, setCategory] = useState('');
  const [location, setLocation] = useState('');
  const [severity, setSeverity] = useState<SeverityRating | null>(null);
  const [description, setDescription] = useState('');
  const [photo, setPhoto] = useState<string | null>(null);
  const [toast, setToast] = useState(false);
  const [toastMessage, setToastMessage] = useState('');
  const [toastError, setToastError] = useState(false);

  // Handle toast auto-dismissal with proper cleanup
  useEffect(() => {
    if (toast) {
      const timer = setTimeout(() => {
        setToast(false);
        setToastError(false);
        setToastMessage('');
      }, 3000);
      return () => clearTimeout(timer);
    }
  }, [toast]);

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!category || !location || !severity) return;
    
    try {
      saveDefect({
        id: crypto.randomUUID(),
        photo,
        category: category as DefectCategory,
        location,
        severity,
        description,
        createdAt: new Date().toISOString(),
      });
      
      // Success - reset form and show success toast
      setCategory('');
      setLocation('');
      setSeverity(null);
      setDescription('');
      setPhoto(null);
      setToastMessage('Defect logged successfully');
      setToastError(false);
      setToast(true);
    } catch (error) {
      // Handle localStorage size limit or other errors
      let message = 'Failed to save defect';
      if (error instanceof Error && error.message.includes('QuotaExceededError')) {
        message = 'Photo too large for storage. Please use a smaller image.';
      } else if (error instanceof DOMException && error.name === 'QuotaExceededError') {
        message = 'Photo too large for storage. Please use a smaller image.';
      }
      setToastMessage(message);
      setToastError(true);
      setToast(true);
    }
  }

  function handlePhotoChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onloadend = () => {
      setPhoto(reader.result as string);
    };
    reader.readAsDataURL(file);
  }

  return (
    <div className="min-h-screen p-4">
      <div className="mx-auto max-w-lg">
        <Link href="/" className="text-sm text-blue-600 hover:underline mb-4 inline-block">← Back to Home</Link>
        <h1 className="text-2xl font-bold mb-6">Log Defect</h1>
        {toast && (
          <div
            role="alert"
            className={`fixed top-4 right-4 text-white px-4 py-2 rounded-md shadow-lg z-50 ${
              toastError ? 'bg-red-600' : 'bg-green-600'
            }`}
          >
            {toastMessage}
          </div>
        )}
        <form className="space-y-4" onSubmit={handleSubmit}>
          <div>
            <label htmlFor="category" className="block text-sm font-medium mb-1">
              Category
            </label>
            <select
              id="category"
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              required
              className="w-full border rounded-md p-2"
            >
              <option value="">Select category</option>
              {CATEGORIES.map((cat) => (
                <option key={cat} value={cat}>
                  {cat}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="location" className="block text-sm font-medium mb-1">
              Location
            </label>
            <input
              id="location"
              type="text"
              value={location}
              onChange={(e) => setLocation(e.target.value)}
              required
              placeholder="e.g. Level 3, Unit 5, Bathroom"
              className="w-full border rounded-md p-2"
            />
          </div>
          <div>
            <span className="block text-sm font-medium mb-1">Severity</span>
            <div className="flex gap-2" role="group" aria-label="Severity rating">
              {SEVERITY_LEVELS.map((level) => (
                <button
                  key={level}
                  type="button"
                  onClick={() => setSeverity(level)}
                  className={`w-10 h-10 rounded-md border font-medium ${
                    severity === level
                      ? 'bg-blue-600 text-white border-blue-600'
                      : 'bg-white text-gray-700 border-gray-300'
                  }`}
                  aria-pressed={severity === level}
                >
                  {level}
                </button>
              ))}
            </div>
          </div>
          <div>
            <label htmlFor="description" className="block text-sm font-medium mb-1">
              Description
            </label>
            <textarea
              id="description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Describe the defect..."
              rows={4}
              className="w-full border rounded-md p-2"
            />
          </div>
          <div>
            <label htmlFor="photo" className="block text-sm font-medium mb-1">
              Photo
            </label>
            <input
              id="photo"
              type="file"
              accept="image/*"
              onChange={handlePhotoChange}
              className="w-full"
            />
            {photo && (
              <img
                src={photo}
                alt="Defect preview"
                className="mt-2 w-32 h-32 object-cover rounded-md"
              />
            )}
          </div>
          <button
            type="submit"
            className="w-full bg-blue-600 text-white py-2 rounded-md font-medium"
          >
            Submit Defect
          </button>
        </form>
      </div>
    </div>
  );
}
