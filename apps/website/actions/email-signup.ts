"use server"

import { z } from "zod"
import { Resend } from "resend"
import { WelcomeEmailTemplate } from "@/components/email-templates/welcome"

const WAITLIST_SEGMENT_ID =
  process.env.RESEND_WAITLIST_SEGMENT_ID ?? "8782e76a-9bed-4003-9c86-f56c0d924556"

const FROM_ADDRESS = "Tablet Notes <hello@updates.tablenotes.io>"

const emailSchema = z.object({
  email: z.string().email({ message: "Please enter a valid email address" }),
  name: z.string().min(1, { message: "Please enter your first name" }),
})

function getResend() {
  const apiKey = process.env.EMAIL_PROVIDER_API_KEY
  if (!apiKey) return null
  return new Resend(apiKey)
}

export async function subscribeToNewsletter(formData: FormData) {
  try {
    const email = formData.get("email") as string
    const name = formData.get("name") as string

    const validatedData = emailSchema.parse({ email, name })

    const resend = getResend()
    if (!resend) {
      console.error("Missing EMAIL_PROVIDER_API_KEY environment variable")
      return {
        success: false,
        message: "Server configuration error. Please try again later.",
      }
    }

    const { data: contact, error: contactError } = await resend.contacts.create({
      email: validatedData.email,
      firstName: validatedData.name,
      unsubscribed: false,
      segments: [{ id: WAITLIST_SEGMENT_ID }],
    })

    if (contactError) {
      const isDuplicate =
        contactError.message?.toLowerCase().includes("already") ||
        contactError.name === "validation_error"

      if (!isDuplicate) {
        console.error("Resend contact creation error:", contactError)
        return {
          success: false,
          message: "Failed to join the waitlist. Please try again later.",
        }
      }

      const { error: updateError } = await resend.contacts.update({
        email: validatedData.email,
        firstName: validatedData.name,
      })

      if (updateError) {
        console.error("Resend contact update error:", updateError)
      }

      return {
        success: true,
        message: `Thanks, ${validatedData.name}! You're already on the list. We'll email you when Tablet Notes launches.`,
      }
    }

    console.log("Waitlist contact created:", contact?.id)

    const { error: emailError } = await resend.emails.send({
      from: FROM_ADDRESS,
      to: validatedData.email,
      subject: "You're on the Tablet Notes waitlist",
      html: WelcomeEmailTemplate({
        email: validatedData.email,
        name: validatedData.name,
      }),
    })

    if (emailError) {
      console.error("Resend email error:", emailError)
      return {
        success: true,
        message: `Thanks, ${validatedData.name}! You're on the list. We'll email you when Tablet Notes launches.`,
      }
    }

    return {
      success: true,
      message: `Thanks, ${validatedData.name}! Check your inbox for a confirmation email.`,
    }
  } catch (error) {
    console.error("Newsletter subscription error:", error)

    if (error instanceof z.ZodError) {
      return {
        success: false,
        message: error.issues[0]?.message || "Please check your information and try again.",
      }
    }

    return {
      success: false,
      message: "Something went wrong. Please try again later.",
    }
  }
}
