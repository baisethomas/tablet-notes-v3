"use client"

import Image from "next/image"
import Link from "next/link"
import { motion } from "framer-motion"

const ease = [0.25, 0.1, 0.25, 1]

export function Hero() {
  return (
    <section className="relative min-h-screen flex flex-col items-center pt-16 pb-0 md:pt-24 overflow-hidden selection:bg-[#2F4FA2] selection:text-foreground bg-[#1F1F23]">
      {/* Background Nib Watermark */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 0.03 }}
        transition={{ duration: 1.2, ease: "easeOut" }}
        className="absolute top-0 left-1/2 -translate-x-1/2 w-full max-w-4xl h-full pointer-events-none z-0 flex justify-center nib-watermark"
      >
        <Image
          src="/images/logomark-black.png"
          alt=""
          width={600}
          height={600}
          className="mt-[-100px] invert"
          aria-hidden="true"
        />
      </motion.div>

      {/* Navigation / Logo */}
      <motion.header
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, ease, delay: 0.1 }}
        className="relative z-10 w-full max-w-6xl mx-auto px-6 mb-16 md:mb-24 flex justify-center"
      >
        <span className="tracking-[0.2em] text-lg font-medium text-foreground/90">
          Tablet Notes
        </span>
      </motion.header>

      {/* Main Content */}
      <div className="relative z-10 w-full max-w-2xl px-6 text-center mx-auto">
        <motion.h1
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, ease, delay: 0.2 }}
          className="text-4xl md:text-6xl font-medium tracking-tight text-foreground mb-6 leading-[1.1] text-balance"
        >
          Write it on the tablet of your heart.
        </motion.h1>

        <motion.p
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, ease, delay: 0.35 }}
          className="text-sm md:text-base text-foreground/70 italic font-normal mb-8 max-w-xl mx-auto leading-relaxed"
        >
          {'"Let love and faithfulness never leave you; bind them around your neck, write them on the tablet of your heart." \u2014 Proverbs 3:3'}
        </motion.p>

        <motion.h2
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, ease, delay: 0.5 }}
          className="text-lg md:text-xl text-foreground/85 font-normal tracking-tight mb-2"
        >
          Most sermons fade by Sunday afternoon.<br />
          Tablet Notes is built to help the ones that matter endure.
        </motion.h2>

        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.4, delay: 0.6 }}
          className="text-sm text-foreground/60 mb-10 tracking-wide uppercase"
        >
          Coming to iPhone
        </motion.p>

        {/* CTA Button */}
        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4, ease, delay: 0.65 }}
        >
          <Link
            href="#waitlist"
            className="inline-block bg-[#2F4FA2] text-foreground text-sm font-medium tracking-wide uppercase px-8 py-4 rounded hover:bg-[#2F4FA2]/90 transition-colors"
          >
            Notify me at launch
          </Link>
          <p className="text-xs text-foreground/40 mt-4 mb-20">No spam. One email at launch.</p>
        </motion.div>
      </div>

      {/* Bottom Gradient Fade */}
      <div className="absolute bottom-0 left-0 right-0 h-[50%] bg-gradient-to-t from-[#1F1F23] via-[#1F1F23]/60 to-transparent z-30 pointer-events-none" />

      {/* Device Mockups */}
      <div className="relative z-10 w-full max-w-5xl mx-auto px-6 mt-auto flex justify-center items-end h-[450px] md:h-[600px]">
        {/* Secondary Device (Dark Mode) - Offset Left/Back */}
        <motion.div
          initial={{ opacity: 0, y: 60 }}
          animate={{ opacity: 0.9, y: 0 }}
          transition={{ duration: 0.7, ease, delay: 0.8 }}
          className="absolute bottom-[-50px] left-1/2 -translate-x-[75%] md:-translate-x-[70%] w-[240px] md:w-[300px] scale-90 origin-bottom-right z-10"
        >
          <Image
            src="/images/hero-phone-dark.png"
            alt="Tablet Notes app in dark mode showing AI-generated sermon summary"
            width={300}
            height={620}
            className="w-full h-auto drop-shadow-2xl"
            priority
          />
        </motion.div>

        {/* Primary Device (Light Mode) - Center/Front */}
        <motion.div
          initial={{ opacity: 0, y: 80 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, ease, delay: 0.75 }}
          className="relative bottom-[-40px] w-[260px] md:w-[320px] z-20"
        >
          <Image
            src="/images/hero-phone-light.png"
            alt="Tablet Notes app in light mode showing AI-generated sermon summary"
            width={320}
            height={660}
            className="w-full h-auto drop-shadow-[0_20px_50px_rgba(0,0,0,0.5)]"
            priority
          />
        </motion.div>
      </div>
    </section>
  )
}
