"use client"

import { useState, useTransition } from "react"
import { subscribeToNewsletter } from "@/actions/email-signup"

interface SignupFormProps {
  variant: "dark" | "blue"
}

export function SignupForm({ variant }: SignupFormProps) {
  const [firstName, setFirstName] = useState("")
  const [email, setEmail] = useState("")
  const [message, setMessage] = useState<string | null>(null)
  const [isSuccess, setIsSuccess] = useState(false)
  const [isPending, startTransition] = useTransition()

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    setMessage(null)

    const formData = new FormData()
    formData.set("name", firstName.trim())
    formData.set("email", email.trim())

    startTransition(async () => {
      const result = await subscribeToNewsletter(formData)

      if (result.success) {
        setIsSuccess(true)
        setMessage(result.message)
      } else {
        setMessage(result.message)
      }
    })
  }

  if (isSuccess) {
    return (
      <div className="w-full mx-auto mb-4">
        <p className={variant === "dark" ? "text-foreground/80 text-sm" : "text-[#FFFFFF]/90 text-sm"}>
          {message}
        </p>
      </div>
    )
  }

  const isDark = variant === "dark"
  const inputBg = isDark ? "bg-[#26262b]" : "bg-[#385bb5]"
  const inputBorder = isDark ? "border-foreground/10" : "border-foreground/20"
  const inputPlaceholder = isDark ? "placeholder-foreground/40" : "placeholder-foreground/60"
  const inputFocus = isDark ? "focus:border-foreground/30" : "focus:border-foreground/50"
  const buttonClasses = isDark
    ? "bg-[#2F4FA2] hover:bg-[#243D7C] text-foreground disabled:opacity-60"
    : "bg-[#FFFFFF] hover:bg-[#FFFFFF]/90 text-[#2F4FA2] disabled:opacity-60"

  return (
    <div className="w-full mx-auto mb-4">
      <form
        onSubmit={handleSubmit}
        className="flex flex-col gap-3 w-full lg:flex-row lg:items-stretch"
      >
        <input
          type="text"
          name="name"
          placeholder="First Name"
          value={firstName}
          onChange={(e) => setFirstName(e.target.value)}
          required
          disabled={isPending}
          className={`w-full lg:w-auto lg:min-w-[10rem] lg:flex-shrink-0 ${inputBg} border ${inputBorder} text-foreground ${inputPlaceholder} text-sm px-4 py-3 rounded-md focus:outline-none ${inputFocus} transition-colors disabled:opacity-60`}
        />
        <input
          type="email"
          name="email"
          placeholder="Email Address"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          disabled={isPending}
          className={`w-full lg:flex-1 lg:min-w-[12rem] ${inputBg} border ${inputBorder} text-foreground ${inputPlaceholder} text-sm px-4 py-3 rounded-md focus:outline-none ${inputFocus} transition-colors disabled:opacity-60`}
        />
        <button
          type="submit"
          disabled={isPending}
          className={`w-full lg:w-auto lg:flex-shrink-0 whitespace-nowrap ${buttonClasses} text-sm font-medium px-6 py-3 rounded-md transition-colors duration-200`}
        >
          {isPending ? "Joining..." : "Notify me at launch"}
        </button>
      </form>
      {message && !isSuccess && (
        <p className="mt-3 text-sm text-red-300">{message}</p>
      )}
      <p className={`mt-3 text-xs ${isDark ? "text-foreground/40" : "text-[#FFFFFF]/60"}`}>
        No spam. One email at launch.
      </p>
    </div>
  )
}
