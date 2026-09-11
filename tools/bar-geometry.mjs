import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

function readJson(program, args) {
  const result = spawnSync(program, args, { encoding: "utf8", timeout: 2000, maxBuffer: 1024 * 1024 });
  if (result.error || result.status !== 0)
    throw new Error(`${program}: ${result.error?.message || result.stderr.trim() || `exit ${result.status}`}`);
  return JSON.parse(result.stdout);
}

export function measuredBarSnapshot(widgets, monitors, layers) {
  // The legacy IPC does not identify each widget's output. Never guess which
  // monitor it belongs to, even when two outputs have identical dimensions.
  if (!Array.isArray(monitors) || monitors.length !== 1)
    throw new Error("The bar measurement API does not identify outputs on multi-monitor desktops.");
  const monitor = monitors[0];
  if (!monitor || typeof monitor.name !== "string" ||
      !["width", "height", "scale", "x", "y", "transform"].every(key => Number.isFinite(monitor[key])) ||
      monitor.scale <= 0 || monitor.width <= 0 || monitor.height <= 0)
    throw new Error("Invalid monitor geometry.");
  const rotated = monitor.transform % 2 !== 0;
  const width = Math.round((rotated ? monitor.height : monitor.width) / monitor.scale);
  const height = Math.round((rotated ? monitor.width : monitor.height) / monitor.scale);
  const levels = layers?.[monitor.name]?.levels;
  const bars = Object.values(levels || {}).flat().filter(layer => layer?.namespace === "omarchy-bar");
  if (bars.length !== 1) throw new Error("No unambiguous measured Omarchy bar layer.");
  const bar = bars[0];
  if (!["x", "y", "w", "h", "alpha"].every(key => Number.isFinite(bar[key])) ||
      bar.w <= 0 || bar.h <= 0 || bar.alpha <= 0 ||
      bar.x < monitor.x || bar.y < monitor.y ||
      bar.x + bar.w > monitor.x + width || bar.y + bar.h > monitor.y + height)
    throw new Error("The bar layer is hidden or outside its output.");
  if (!Array.isArray(widgets) || widgets.length === 0) throw new Error("The active bar exposes no widget measurements.");
  const barEdge = bar.w >= bar.h
    ? (bar.y - monitor.y <= height - (bar.y - monitor.y) - bar.h ? "top" : "bottom")
    : (bar.x - monitor.x <= width - (bar.x - monitor.x) - bar.w ? "left" : "right");
  const measured = widgets.map(widget => {
    if (!widget || typeof widget.id !== "string" ||
        !["x", "y", "width", "height"].every(key => Number.isFinite(widget[key])) ||
        typeof widget.visible !== "boolean" || typeof widget.itemVisible !== "boolean" ||
        widget.width < 0 || widget.height < 0)
      throw new Error("Invalid bar widget measurement.");
    if (widget.visible && widget.itemVisible && (widget.x < 0 || widget.y < 0 ||
        widget.x + widget.width > bar.w || widget.y + widget.height > bar.h))
      throw new Error("Widget coordinates do not fit the measured bar layer.");
    return { id: widget.id, x: widget.x + bar.x - monitor.x, y: widget.y + bar.y - monitor.y,
      width: widget.width, height: widget.height, visible: widget.visible, itemVisible: widget.itemVisible, barEdge };
  });
  return { version: 1, screens: [{ name: monitor.name, width, height, widgets: measured }] };
}

export function collectBarGeometry(read = readJson) {
  const monitors = read("hyprctl", ["-j", "monitors"]);
  const layers = read("hyprctl", ["-j", "layers"]);
  const widgets = read("omarchy-shell", ["shell", "debugBarGeometry"]);
  const afterLayers = read("hyprctl", ["-j", "layers"]);
  const afterMonitors = read("hyprctl", ["-j", "monitors"]);
  const topology = values => values.map(({ name, x, y, width, height, scale, transform }) =>
    ({ name, x, y, width, height, scale, transform }));
  const barLayers = values => Object.fromEntries(Object.entries(values).map(([name, output]) =>
    [name, Object.values(output.levels || {}).flat().filter(layer => layer.namespace === "omarchy-bar")]));
  if (JSON.stringify(topology(monitors)) !== JSON.stringify(topology(afterMonitors)) ||
      JSON.stringify(barLayers(layers)) !== JSON.stringify(barLayers(afterLayers)))
    throw new Error("The desktop layout changed during bar measurement.");
  return measuredBarSnapshot(widgets, monitors, layers);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { console.log(JSON.stringify(collectBarGeometry())); }
  catch (error) {
    console.error(`Bar measurement unavailable: ${error.message}`);
    process.exitCode = 1;
  }
}
