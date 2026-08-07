-- learning_curve.lua -- inline SVG sketch of a learning curve
--
-- {{< lc curve=2 >}}  slow curve (flat start, steep finish)
-- {{< lc curve=1 >}}  straight line
-- {{< lc curve=0.5 >}} fast curve (steep start, plateau)
--
-- The curve is the power law y = x^curve over the unit square, so `curve` is
-- literally the exponent: 2 gives the parabola y = x^2, 1 a straight line, and
-- c / (1/c) are mirror images of each other across the diagonal.
--
-- Options (all optional, shown with their defaults):
--
--   curve=2              exponent; also accepted positionally, {{< lc 2 >}}
--   height=1em           any CSS length; the width follows the 3:2 aspect ratio
--   offset=-0.15em       vertical-align of the inline box
--   color=#000           curve stroke; any CSS color, including `currentColor`
--                        to follow the color of the surrounding text
--   axis-color=#b0b0b0   axes stroke, same rules as `color`
--   weight=1.8           curve stroke width in viewBox units; the axes use 3/4
--   label=""             accessible name; without it the SVG is aria-hidden
--   class=""             extra CSS classes, appended after `lc`
--
-- Note that `currentColor` only resolves for the inline-SVG (HTML) output. The
-- non-HTML fallback below hands pandoc a standalone SVG file, which has no
-- surrounding text to inherit from, so there it falls back to black.

local function isEmpty(s)
  return s == nil or s == ''
end

local str = pandoc.utils.stringify

-- Axes box: 30 x 20 user units (the required 3:2 ratio) inset by a 1 unit
-- margin inside the viewBox, so round stroke caps are never clipped.
local X0, Y0 = 1, 21   -- origin, bottom left
local W, H = 30, 20
local SAMPLES = 64

-- Sampled path for y = x^p from the origin to the top right corner.
local function curve_path(p)
  local pts = {}
  for i = 0, SAMPLES do
    local t = i / SAMPLES
    local x, y
    if p >= 1 then
      -- slope is finite at the origin: sample uniformly in x
      x, y = t, t ^ p
    else
      -- slope is infinite at the origin: sample uniformly in y instead,
      -- which is the exact mirror of the branch above
      x, y = t ^ (1 / p), t
    end
    pts[#pts + 1] = string.format("%.3f,%.3f", X0 + W * x, Y0 - H * y)
  end
  return "M " .. table.concat(pts, " L ")
end

local function learning_curve(args, kwargs)
  local curve = tonumber(str(kwargs["curve"]))
  if curve == nil and args[1] ~= nil then
    curve = tonumber(str(args[1]))
  end
  if curve == nil then
    curve = 2
  end
  -- curve <= 0 degenerates into a step, huge exponents into the axes themselves
  curve = math.max(0.1, math.min(20, curve))

  local height = str(kwargs["height"])
  if isEmpty(height) then
    height = "1em"
  end
  local offset = str(kwargs["offset"])
  if isEmpty(offset) then
    offset = "-0.15em"
  end
  local color = str(kwargs["color"])
  if isEmpty(color) then
    color = "currentColor"
  end
  local axis_color = str(kwargs["axis-color"])
  if isEmpty(axis_color) then
    axis_color = "#b0b0b0"
  end
  local weight = tonumber(str(kwargs["weight"])) or 1.8
  local label = str(kwargs["label"])
  local class = str(kwargs["class"])

  local extra_class = ""
  if not isEmpty(class) then
    extra_class = " " .. class
  end

  -- Only the height is set: with a viewBox in place the renderer derives the
  -- width from the aspect ratio, so the 3:2 box can never be distorted.
  local style = string.format(
    "display:inline-block;height:%s;width:auto;vertical-align:%s",
    height, offset
  )

  local title, aria = "", ' aria-hidden="true"'
  if not isEmpty(label) then
    title = string.format("<title>%s</title>", label)
    aria = ""
  end

  local svg = string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 22" role="img"' ..
    ' class="lc%s" style="%s"%s>%s' ..
    '<g fill="none" stroke-linecap="round" stroke-linejoin="round">' ..
    '<path d="M %g %g L %g %g L %g %g" stroke="%s" stroke-width="%g"/>' ..
    '<path d="%s" stroke="%s" stroke-width="%g"/>' ..
    '</g></svg>',
    extra_class, style, aria, title,
    X0, Y0 - H, X0, Y0, X0 + W, Y0, axis_color, weight * 0.75,
    curve_path(curve), color, weight
  )

  if quarto.doc.isFormat("html:js") then
    return pandoc.RawInline("html", svg)
  end

  -- Non-HTML formats (typst, latex, docx): hand the SVG to pandoc through the
  -- mediabag so the glyph does not silently vanish.
  local slug = tostring(curve):gsub("%.", "_")
  local name = string.format("learning-curve-%s.svg", slug)
  pandoc.mediabag.insert(name, "image/svg+xml", svg)
  return pandoc.Image({}, name, "", pandoc.Attr("", { "lc" }, { height = height }))
end

return {
  ['lc'] = learning_curve,
  ['learning_curve'] = learning_curve
}
