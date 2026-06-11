# The Problem Expresto Solves

## The Situation

When someone has a medical emergency, a fire, or a threat to their safety, the first thing they do is call emergency services. They speak. They describe what is happening, where they are, and how bad it is. The operator on the other end asks questions. The caller answers. Help is dispatched.

That entire system depends on one thing: the ability to speak.

For the roughly **430 million people worldwide** who are deaf or hard of hearing, and the millions more with speech impairments, that system simply does not work. A deaf person in danger cannot call 911 and describe their emergency. They cannot answer the operator's questions. In many countries, text-based emergency services exist but are slower, less reliable, and far less widely known than a voice call. In a crisis, seconds matter — and the current infrastructure was not designed with them in mind.

---

## The Gap

The problem is not that deaf and mute people cannot communicate. Sign language is a complete, expressive, natural language. The problem is that **emergency services infrastructure does not speak it**.

There is no bridge. When a deaf person is in danger, they face a choice between systems that were never built for them: a voice call they cannot make, a text system that may not be available, or silence.

---

## What Expresto Does

Expresto is an emergency calling app built specifically for deaf and mute users. It creates a real-time communication bridge between a person in crisis and a trained operator or AI assistant — using sign language as the input.

Here is how it works in practice:

1. **The user opens the app and starts an emergency call.** Their phone camera activates and begins reading their hands.

2. **The app recognizes their sign language in real time**, classifying gestures and translating them into text. That text is analyzed to understand the nature of the emergency and assigned an urgency score. Active calls are surfaced in the operator dashboard ranked by priority, so the most critical situations are always at the top.

3. **Lower-priority calls — such as a minor injury — are handled automatically by an AI assistant**, which responds immediately without waiting for a human operator. For higher-priority or complex situations, a human operator picks up the call from the queue, reads the translated signs, and takes over the conversation directly.

4. **The response is delivered back to the user as animated sign language** — displayed on screen as a signing avatar so the user receives the answer in their own language, without needing to read.

5. **Location, urgency scoring, and call metadata** are surfaced to the operator automatically, so help can be dispatched without the user having to spell out their address under stress.

---

## Why It Matters

This is not an accessibility feature bolted onto an existing product. It is a rethinking of what an emergency call looks like when voice is not an option.

For a deaf person, Expresto means the difference between being able to call for help and not. It means being understood in a moment of crisis. It means getting a response they can actually receive. It means equal access to the most fundamental public safety resource that exists.

The technology to do this exists. The need has always been there. Expresto closes the gap between the two.

---

## How We Built the Models

Both the sign language classifier and the facial urgency detector were trained from scratch on existing datasets. We studied the data carefully, then applied additional preprocessing to improve coverage: samples were augmented by varying orientation, mirroring, tilting, and other geometric transformations to make the models more robust to real-world conditions. We also tuned the hyperparameters for each model independently.

The results were meaningful. The sign language classifier improved by **2%** over the baseline dataset accuracy, and the facial urgency detector improved by **7%** — both measured against the original dataset before augmentation. These gains translate directly into fewer misclassified signs and more reliable urgency detection during a live call.
