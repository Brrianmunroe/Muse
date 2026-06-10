// ---------- Photo data ----------

const PHOTOS = [
  {
    src: "images/photo_1011.jpg",
    tags: ["maritime", "cool palette", "solitude"],
    description:
      "A lone figure on still water — muted blues and a horizon line that gives the frame its calm, editorial weight.",
    notes: "Reference for Q2 mood board",
    source: "Saved from Instagram · Mar 12, 2026",
  },
  {
    src: "images/photo_1015.jpg",
    tags: ["river bend", "earth tones", "depth"],
    description:
      "Layered valley with a winding river — natural leading lines and a soft atmospheric fade toward the background.",
    notes: "",
    source: "Saved from Pinterest · Mar 9, 2026",
  },
  {
    src: "images/photo_1025.jpg",
    tags: ["warm palette", "portrait", "texture"],
    description:
      "Close crop with warm fur tones against a soft ground — strong subject isolation and gentle tonal gradients.",
    notes: "Try this warmth for the onboarding screens",
    source: "Saved from Behance · Mar 4, 2026",
  },
  {
    src: "images/photo_1043.jpg",
    tags: ["alpine", "scale contrast", "natural light"],
    description:
      "Granite walls over a still river — huge scale contrast and a warm-on-cool palette of stone, pine, and sky.",
    notes: "",
    source: "Saved from Are.na · Feb 27, 2026",
  },
  {
    src: "images/photo_1080.jpg",
    tags: ["gallery red", "repetition", "macro"],
    description:
      "Strawberries in tight repetition — one saturated hue carrying the whole frame, with texture doing the rest.",
    notes: "Good palette anchor for the tags rework",
    source: "Saved from Safari · Feb 20, 2026",
  },
];

// ---------- Elements ----------

const phone = document.getElementById("phone");
const photoEl = document.getElementById("photo");
const ambientA = document.getElementById("ambientA");
const ambientB = document.getElementById("ambientB");
const tagsEl = document.getElementById("tags");
const descriptionEl = document.getElementById("description");
const notesField = document.getElementById("notesField");
const sourceEl = document.getElementById("source");
const counterEl = document.getElementById("counter");
const glassCard = document.getElementById("glassCard");

let index = 0;
let activeAmbient = ambientA;
let transitioning = false;

// In-memory note edits, like the app's preview mode
const editedNotes = new Map();

// ---------- Tone-matched ambient gradient ----------

/**
 * Downsamples the image to a tiny canvas and produces the two stops of the
 * ambient gradient. Pixels are weighted by saturation so vivid tones drive
 * the glow instead of being averaged away by greys, then the result gets a
 * saturation boost. The bottom stop is darkened so the glass card reads.
 */
function extractGradient(img) {
  const SIZE = 16;
  const canvas = document.createElement("canvas");
  canvas.width = SIZE;
  canvas.height = SIZE;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(img, 0, 0, SIZE, SIZE);
  const { data } = ctx.getImageData(0, 0, SIZE, SIZE);

  const half = SIZE / 2;
  const top = { r: 0, g: 0, b: 0, w: 0 };
  const bottom = { r: 0, g: 0, b: 0, w: 0 };

  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const i = (y * SIZE + x) * 4;
      const r = data[i];
      const g = data[i + 1];
      const b = data[i + 2];
      const max = Math.max(r, g, b);
      const min = Math.min(r, g, b);
      // Saturation-weighted: vivid pixels count up to 5x more than greys
      const weight = 1 + ((max - min) / 255) * 4;
      const target = y < half ? top : bottom;
      target.r += r * weight;
      target.g += g * weight;
      target.b += b * weight;
      target.w += weight;
    }
  }

  const topColor = boostSaturation(top.r / top.w, top.g / top.w, top.b / top.w, 1.45, [0.3, 0.62]);
  const bottomColor = boostSaturation(bottom.r / bottom.w, bottom.g / bottom.w, bottom.b / bottom.w, 1.45, [0.1, 0.24]);

  return `linear-gradient(170deg, ${topColor} 0%, ${bottomColor} 100%)`;
}

/** Boost saturation and clamp lightness (HSL) so every photo glows. */
function boostSaturation(r, g, b, satFactor, [minL, maxL]) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  let h = 0;
  let l = (max + min) / 2;
  let s = 0;

  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
    else if (max === g) h = ((b - r) / d + 2) / 6;
    else h = ((r - g) / d + 4) / 6;
  }

  s = Math.min(1, s * satFactor);
  l = Math.min(maxL, Math.max(minL, l));

  return `hsl(${Math.round(h * 360)}, ${Math.round(s * 100)}%, ${Math.round(l * 100)}%)`;
}

function crossfadeAmbient(gradient) {
  const incoming = activeAmbient === ambientA ? ambientB : ambientA;
  incoming.style.background = gradient;
  incoming.style.opacity = "1";
  activeAmbient.style.opacity = "0";
  activeAmbient = incoming;
}

// ---------- Rendering ----------

function renderMetadata(photo) {
  tagsEl.innerHTML = "";
  for (const tag of photo.tags) {
    const chip = document.createElement("span");
    chip.className = "tag";
    chip.textContent = tag;
    tagsEl.appendChild(chip);
  }
  descriptionEl.textContent = photo.description;
  notesField.value = editedNotes.get(photo.src) ?? photo.notes;
  sourceEl.textContent = photo.source;
  counterEl.textContent = `${index + 1} of ${PHOTOS.length}`;
}

function show(newIndex, { animate = true } = {}) {
  if (transitioning) return;
  index = (newIndex + PHOTOS.length) % PHOTOS.length;
  const photo = PHOTOS[index];

  if (!animate) {
    loadAndApply(photo);
    return;
  }

  transitioning = true;
  photoEl.classList.add("is-leaving");
  glassCard.classList.add("is-leaving");

  setTimeout(() => {
    loadAndApply(photo, () => {
      photoEl.classList.remove("is-leaving");
      glassCard.classList.remove("is-leaving");
      transitioning = false;
    });
  }, 320);
}

function loadAndApply(photo, done) {
  const loader = new Image();
  loader.crossOrigin = "anonymous";
  loader.onload = () => {
    photoEl.src = photo.src;
    crossfadeAmbient(extractGradient(loader));
    renderMetadata(photo);
    if (done) done();
  };
  loader.src = photo.src;
}

// ---------- Interactions ----------

document.getElementById("prevBtn").addEventListener("click", () => show(index - 1));
document.getElementById("closeBtn").addEventListener("click", () => {
  // Decorative in this single-screen prototype
  glassCard.animate(
    [{ transform: "scale(1)" }, { transform: "scale(0.98)" }, { transform: "scale(1)" }],
    { duration: 200 }
  );
});

document.addEventListener("keydown", (e) => {
  if (document.activeElement === notesField) return;
  if (e.key === "ArrowRight") show(index + 1);
  if (e.key === "ArrowLeft") show(index - 1);
});

// Touch / trackpad swipe
let touchStartX = null;
phone.addEventListener("touchstart", (e) => {
  touchStartX = e.touches[0].clientX;
}, { passive: true });

phone.addEventListener("touchend", (e) => {
  if (touchStartX === null) return;
  const dx = e.changedTouches[0].clientX - touchStartX;
  touchStartX = null;
  if (Math.abs(dx) < 50) return;
  show(dx < 0 ? index + 1 : index - 1);
});

// Mouse drag swipe for desktop testing
let mouseStartX = null;
phone.addEventListener("mousedown", (e) => {
  if (e.target === notesField) return;
  mouseStartX = e.clientX;
});
window.addEventListener("mouseup", (e) => {
  if (mouseStartX === null) return;
  const dx = e.clientX - mouseStartX;
  mouseStartX = null;
  if (Math.abs(dx) < 60) return;
  show(dx < 0 ? index + 1 : index - 1);
});

notesField.addEventListener("input", () => {
  editedNotes.set(PHOTOS[index].src, notesField.value);
});

// ---------- Init ----------

const startParam = parseInt(new URLSearchParams(location.search).get("i"), 10);
show(Number.isFinite(startParam) ? startParam : 0, { animate: false });
