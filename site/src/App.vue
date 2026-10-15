<script setup>
import { computed, ref } from 'vue'
import manualScreen from '../../assets/manual_plan.jpg'
import estimateScreen from '../../assets/toll_estimate.jpg'
import savedScreen from '../../assets/saved_routes.jpg'
import appIcon from '../../android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png'
import mitLicense from '../../LICENSE?url'
import dmSansLicense from '../../licenses/DM-Sans-OFL.txt?url'
import manropeLicense from '../../licenses/Manrope-OFL.txt?url'
import vueLicense from '../../licenses/Vue-MIT.txt?url'

const repository = 'https://github.com/Alchemist-Aloha/NovaToll'
const releases = `${repository}/releases/latest`
const activeStep = ref(0)
const preview = ref(null)
const previewImage = ref(null)
const steps = [
  {
    label: 'Plan your route',
    title: 'Your starting point. Your destination.',
    description: 'Pick your highway, direction, entry, and exit. Reachable destinations include supported connections beyond your starting highway. Prefer the map? Pan, zoom, or search for a ramp.',
    image: manualScreen,
    alt: 'Nova Toll manual route planner with starting highway, direction, entry, and connected destination controls',
  },
  {
    label: 'Understand your estimate',
    title: 'See how the whole trip adds up.',
    description: 'Combine available operator estimates across highways. Review the individual segments, freshness warnings, and official toll websites. If a price is missing, you see a known subtotal instead of a misleading total.',
    image: estimateScreen,
    alt: 'Nova Toll map showing an example $25.85 estimate from I-495 to I-66 west with a rate freshness warning',
  },
  {
    label: 'Save your usual trips',
    title: 'The routes you take, ready for next time.',
    description: 'Keep your commute and other frequent trips together on your device. Load a saved route to check a fresh estimate, or delete it when you no longer need it. No account or sync required.',
    image: savedScreen,
    alt: 'Nova Toll saved trips including an I-495 to I-66 route, an outside-to-inside I-66 route, and an I-395 route',
  },
]
const currentStep = computed(() => steps[activeStep.value])
const operators = [
  { roads: 'I-495 · I-95 · I-395', name: 'Express Lanes', url: 'https://www.expresslanes.com/map-your-trip' },
  { roads: 'I-66 inside the Beltway', name: 'VDOT', url: 'https://vai66tolls.com' },
  { roads: 'I-66 outside the Beltway', name: 'Ride66Express', url: 'https://ride66express.com/pricing/plan-your-trip/' },
]

function openPreview(image) {
  previewImage.value = image
  preview.value.showModal()
}
</script>

<template>
  <a class="skip-link" href="#main">Skip to content</a>
  <header class="site-header wrap">
    <a class="brand" href="#" aria-label="Nova Toll home">
      <img :src="appIcon" width="36" height="36" alt="" />
      <span>Nova Toll</span>
    </a>
    <nav aria-label="Main navigation">
      <a href="#how-it-works">The app</a>
      <a href="#coverage">Coverage</a>
      <a class="nav-download" :href="releases">Get for Android <span aria-hidden="true">↗</span></a>
    </nav>
  </header>

  <main id="main">
    <section class="hero wrap" aria-labelledby="hero-title">
      <div class="hero-copy">
        <p class="eyebrow">A little clarity for Northern Virginia drivers</p>
        <h1 id="hero-title">Know the toll.<br /><span>Before you go.</span></h1>
        <p class="hero-description">Dynamic tolls can be surprisingly high. Crossing highways shouldn’t mean piecing together the price yourself.</p>
        <p class="hero-support">Nova Toll brings your connected express-lane trip into one clear estimate, right on your Android phone.</p>
        <div class="hero-actions">
          <a class="button button-dark" :href="releases">Get Nova Toll for Android <span aria-hidden="true">↗</span></a>
          <a class="text-link" href="#how-it-works">Take a look <span aria-hidden="true">↓</span></a>
        </div>
        <p class="quiet">No account. Your saved trips stay on your device.</p>
      </div>
      <div class="hero-visual">
        <div class="phone-backdrop" aria-hidden="true"></div>
        <p class="visual-note">One route.<br /><em>A clearer picture.</em></p>
        <button class="phone hero-phone" @click="openPreview(steps[1])" aria-label="Enlarge the trip estimate screenshot">
          <img :src="estimateScreen" width="945" height="2048" :alt="steps[1].alt" fetchpriority="high" />
        </button>
        <p class="image-caption">Actual app screen. Example estimate; prices change.</p>
      </div>
    </section>

    <div class="corridor-band">
      <div class="wrap corridor-content">
        <p>Across your Northern Virginia route</p>
        <div class="corridor-names" aria-label="Supported highways">
          <span>I-495</span><span>I-95</span><span>I-395</span><span>I-66 <small>inside &amp; outside</small></span>
        </div>
      </div>
    </div>

    <section id="how-it-works" class="walkthrough wrap" aria-labelledby="walkthrough-title">
      <div class="walkthrough-copy">
        <p class="eyebrow">A better view of your trip</p>
        <h2 id="walkthrough-title">A few taps.<br />Fewer toll surprises.</h2>
        <div class="step-controls" aria-label="Explore the app screens">
          <button v-for="(step, index) in steps" :key="step.label" :aria-pressed="activeStep === index" @click="activeStep = index">
            <span>{{ step.label }}</span><span aria-hidden="true">↗</span>
          </button>
        </div>
        <div class="step-description" aria-live="polite" aria-atomic="true">
          <h3>{{ currentStep.title }}</h3>
          <p>{{ currentStep.description }}</p>
        </div>
      </div>
      <div class="demo-visual">
        <button class="phone demo-phone" @click="openPreview(currentStep)" :aria-label="`Enlarge ${currentStep.label.toLowerCase()} screenshot`">
          <img :key="currentStep.image" :src="currentStep.image" :alt="currentStep.alt" width="945" height="2048" loading="lazy" />
        </button>
        <span class="demo-caption">Select a step to explore · Tap the screen to enlarge</span>
      </div>
    </section>

    <section id="coverage" class="coverage" aria-labelledby="coverage-title">
      <div class="wrap coverage-grid">
        <div>
          <p class="eyebrow">Different roads. One journey.</p>
          <h2 id="coverage-title">Connect the roads.<br />See the full picture.</h2>
          <p class="section-intro">Estimate supported connections between I-66 inside and outside the Beltway and the I-495, I-95, and I-395 Express Lanes.</p>
          <p class="coverage-note">Every estimate includes links to the operators involved, so you can check the source yourself.</p>
        </div>
        <div class="operator-list">
          <a v-for="operator in operators" :key="operator.name" :href="operator.url" target="_blank" rel="noopener noreferrer">
            <span><strong>{{ operator.roads }}</strong><small>{{ operator.name }} · Official toll planner</small></span>
            <span aria-hidden="true">↗</span><span class="sr-only"> (opens in a new tab)</span>
          </a>
        </div>
      </div>
    </section>

    <section id="privacy" class="details-section wrap" aria-label="Privacy and estimate information">
      <div class="privacy-copy">
        <p class="eyebrow">Your route stays yours</p>
        <h2>A trip planner.<br />No account needed.</h2>
        <p>Saved routes live on your device. Location is optional and used for a one-time nearby-entry suggestion. Your coordinates aren’t sent to toll services.</p>
        <a class="text-link" :href="repository">Explore the project on GitHub <span aria-hidden="true">↗</span></a>
      </div>
      <div class="questions">
        <details open>
          <summary>How should I use an estimate?</summary>
          <p>Use it to plan ahead, while parked or with a passenger. Estimates can change before you reach a toll segment. Posted roadside prices govern; refresh time does not guarantee a newly updated rate.</p>
        </details>
        <details>
          <summary>What if part of the price is unavailable?</summary>
          <p>Nova Toll flags unavailable or closed segments and incomplete totals. A known subtotal covers only the available components. A missing price never means that segment is free.</p>
        </details>
        <details>
          <summary>Is this a navigation app?</summary>
          <p>Nova Toll is an independent toll trip planner. Map markers are approximate, and construction notes in the artwork are historical. Verify ramp names and road signs.</p>
        </details>
      </div>
    </section>

    <section class="download-section" aria-labelledby="download-title">
      <div class="wrap download-content">
        <div><p class="eyebrow">Before your next trip</p><h2 id="download-title">Choose your route<br />with a little more clarity.</h2></div>
        <div class="download-action">
          <a class="button button-peach" :href="releases">Download for Android <span aria-hidden="true">↗</span></a>
          <p>Choose the ARM64 APK for most current phones.<br />All three device variants are on GitHub Releases.</p>
        </div>
      </div>
    </section>
  </main>

  <footer class="wrap site-footer">
    <a class="brand" href="#">Nova Toll</a>
    <p>An independent Northern Virginia trip planner.</p>
    <a :href="repository">GitHub <span aria-hidden="true">↗</span></a>
    <p class="license-note">
      Original code: <a :href="mitLicense" download="Nova-Toll-LICENSE.txt">MIT License</a>.
      Font licenses: <a :href="dmSansLicense">DM Sans</a> · <a :href="manropeLicense">Manrope</a>.
      <a :href="vueLicense">Vue license</a> ·
      <a :href="`${repository}/blob/main/THIRD_PARTY_NOTICES.md`">Third-party asset notices</a>.
    </p>
  </footer>

  <dialog ref="preview" class="screenshot-dialog" aria-label="App screenshot preview" @click="($event.target === preview) && preview.close()">
    <button class="dialog-close" @click="preview.close()" autofocus>Close <span aria-hidden="true">×</span></button>
    <img v-if="previewImage" :src="previewImage.image" :alt="previewImage.alt" />
  </dialog>
</template>
