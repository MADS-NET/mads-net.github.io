// =====================================================================
//  MADS flyer — Typst brand template
//  Colors, fonts and reusable components matching the MADS website
//  (see _brand.yml / _vars.scss). Used by flyer.qmd.
// =====================================================================

// --- Brand palette (from _brand.yml) --------------------------------
#let mads-orange       = rgb("#DA6A15")   // primary
#let mads-orange-light = rgb("#F08B36")
#let mads-blue         = rgb("#1585DA")   // complement of orange (accent)
#let mads-blue-dark    = rgb("#0C5E9E")
#let mads-pink         = rgb("#FF3D7F")   // danger / pop accent
#let mads-ink          = rgb("#1A1A1A")
#let mads-paper        = rgb("#F9F9F9")
#let mads-cloud        = rgb("#FBEFE4")   // very light orange tint
#let mads-sky          = rgb("#E6F1FB")   // very light blue tint
#let mads-line         = rgb("#E4E0DB")   // hairline / card border

// --- Fonts (bundled in ./fonts, loaded via font-paths) --------------
#let font-head = "Rubik"
#let font-body = "Open Sans"
#let font-mono = "IBM Plex Mono"

// --- Layout constants -----------------------------------------------
#let PAD = 13mm   // horizontal page padding for full-bleed bands

// A full-bleed horizontal band that keeps content inside PAD margins.
#let band(body, fill: none, top: 7mm, bottom: 7mm) = block(
  width: 100%,
  fill: fill,
  inset: (x: PAD, top: top, bottom: bottom),
  body,
)

// Footer artwork is drawn behind the flyer content and keyed to page number.
#let flyer-footer-background = context {
  let page-no = counter(page).get().first()
  if page-no == 1 {
    place(bottom)[
      #image("images/flyer-footer-industrial-daq-light.png", width: 100%, height: 63mm, fit: "cover")
    ]
  } else if page-no == 2 {
    place(bottom)[
      #image("images/flyer-footer-industrial-daq-dark.png", width: 100%, height: 43mm, fit: "cover")
    ]
  }
}

// Full-bleed footer artwork, cropped to a fixed band height.
#let image-footer(path, h) = image(path, width: 100%, height: h, fit: "cover")

// Two/three color accent stripe used under the header.
#let accent-stripe(h: 3.2mm) = grid(
  columns: (1.7fr, 1fr, 3fr),
  rows: h,
  block(width: 100%, height: h, fill: mads-blue),
  block(width: 100%, height: h, fill: mads-pink),
  block(width: 100%, height: h, fill: mads-orange-light),
)

// Small uppercase section kicker.
#let kicker(txt, color: mads-orange) = text(
  font: font-head, weight: 600, size: 9pt, fill: color, tracking: 2.2pt,
)[#upper(txt)]

// Section title with a colored leading bar.
#let section-title(txt, color: mads-orange) = block(
  inset: (left: 9pt), stroke: (left: 3.5pt + color), below: 6pt, above: 0pt,
)[
  #text(font: font-head, weight: 700, size: 15pt, fill: mads-ink)[#txt]
]

// Rounded pill / chip.
#let chip(txt, fg: white, bg: mads-blue) = box(
  fill: bg, inset: (x: 6.5pt, y: 3pt), radius: 20pt, baseline: 2.5pt,
)[#text(font: font-body, size: 7.8pt, weight: 600, fill: fg)[#txt]]

// Feature card: colored dot + title + one-liner body.
#let feature(title, body, accent: mads-orange) = block(
  fill: white, radius: 7pt, inset: 10pt, width: 100%,
  stroke: 0.6pt + mads-line,
)[
  #stack(dir: ltr, spacing: 6pt,
    box(baseline: 1.5pt, circle(radius: 3.2pt, fill: accent)),
    text(font: font-head, weight: 600, size: 10.5pt, fill: mads-ink)[#title],
  )
  #v(3pt)
  #text(font: font-body, size: 8.3pt, fill: mads-ink.lighten(18%))[#body]
]

// Big number stat (for the stats band, on colored bg).
#let stat(num, label, fg: white) = align(center + horizon)[
  #text(font: font-head, weight: 700, size: 21pt, fill: fg)[#num]
  #v(-2pt)
  #text(font: font-body, size: 7.6pt, weight: 600, fill: fg.transparentize(12%))[
    #upper(label)
  ]
]

// Node used in the source -> filter -> sink flow diagram.
#let flow-node(txt, bg) = box(
  fill: bg, radius: 6pt, inset: (x: 12pt, y: 7pt),
)[#text(font: font-head, weight: 600, size: 10pt, fill: white)[#txt]]

#let flow-arrow = text(font: font-body, size: 15pt, weight: 700, fill: mads-ink.lighten(35%))[→]

// A single "get started" link row: label + mono URL.
#let link-item(label, url, accent: mads-orange) = grid(
  columns: (auto, 1fr), gutter: 7pt, align: (left + horizon, left + horizon),
  box(fill: accent, radius: 3pt, inset: (x: 5pt, y: 2.5pt))[
    #text(font: font-head, size: 7.5pt, weight: 600, fill: white)[#upper(label)]
  ],
  text(font: font-mono, size: 8.5pt, fill: white)[#url],
)

// --- Document setup --------------------------------------------------
#let flyer(doc) = {
  set document(
    title: "MADS — Multi-Agent Distributed System",
    author: "Paolo Bosetti",
  )
  set page(
    paper: "a4",
    margin: 0pt,
    fill: mads-paper,
    background: flyer-footer-background,
  )
  set text(
    font: font-body,
    size: 9.5pt,
    fill: mads-ink,
    lang: "en",
    hyphenate: false,
  )
  set par(justify: false, leading: 0.62em, spacing: 0.9em)
  show link: it => text(fill: mads-blue-dark)[#it]
  doc
}
