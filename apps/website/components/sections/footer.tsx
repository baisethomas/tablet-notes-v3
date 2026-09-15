import Link from "next/link"
import { Facebook, Instagram } from "lucide-react"

export function Footer() {
  return (
    <footer className="bg-[#F7F8FA] py-12 px-6">
      <div className="max-w-6xl mx-auto flex flex-col md:flex-row justify-between items-center text-xs text-[#1F1F23]/50">
        <div className="mb-4 md:mb-0">
          {"\u00A9"} 2026 Tablet Notes
        </div>
        <div className="flex items-center gap-5">
          <Link
            href="https://www.instagram.com/tabletnotesapp/"
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Tablet Notes on Instagram"
            className="hover:text-[#1F1F23] transition-colors"
          >
            <Instagram className="h-4 w-4" />
          </Link>
          <span
            aria-label="Facebook coming soon"
            title="Facebook coming soon"
            className="text-[#1F1F23]/30 cursor-not-allowed"
          >
            <Facebook className="h-4 w-4" />
          </span>
          <Link
            href="/terms"
            className="hover:text-[#1F1F23] transition-colors"
          >
            Terms of Use
          </Link>
          <Link
            href="/privacy"
            className="hover:text-[#1F1F23] transition-colors"
          >
            Privacy Policy
          </Link>
        </div>
      </div>
    </footer>
  )
}
