"""GUI nodes for topng.py: the dumped PlayerGui tree (explicitly set properties) with Roblox's defaults applied, and the
rectangles, clip rects, canvas sizes and text lines that guiengine.luau computed inside the fake engine (the layout is
done there, once, so what the game's scripts read through AbsoluteSize & co. is exactly what gets drawn)."""
import math

GUI_OBJECTS = {
    "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "ViewportFrame",
    "CanvasGroup", "VideoFrame",
}
TEXT_CLASSES = {"TextLabel", "TextButton", "TextBox"}
IMAGE_CLASSES = {"ImageLabel", "ImageButton"}

GREY = [163 / 255, 162 / 255, 165 / 255]
INK27 = [27 / 255, 42 / 255, 53 / 255]

DEFAULTS_COMMON = {
    "Visible": True, "Position": [0, 0, 0, 0], "AnchorPoint": [0, 0], "Rotation": 0, "ZIndex": 1, "LayoutOrder": 0,
    "BackgroundColor3": GREY, "BackgroundTransparency": 0, "BorderSizePixel": 1, "BorderColor3": INK27,
    "BorderMode": "Outline", "ClipsDescendants": False, "AutomaticSize": "None",
}
DEFAULTS = {
    "Frame": {"Size": [0, 100, 0, 100]},
    "ScrollingFrame": {"Size": [0, 100, 0, 100], "CanvasSize": [0, 0, 2, 0], "CanvasPosition": [0, 0], "AutomaticCanvasSize": "None",
                       "ScrollBarThickness": 12, "ScrollBarImageColor3": [0, 0, 0], "ScrollBarImageTransparency": 0,
                       "ScrollingDirection": "XY", "ClipsDescendants": True},
    "TextLabel": {"Size": [0, 200, 0, 50], "Text": "Label"},
    "TextButton": {"Size": [0, 200, 0, 50], "Text": "Button"},
    "TextBox": {"Size": [0, 200, 0, 50], "Text": "", "PlaceholderText": "", "PlaceholderColor3": [0.7, 0.7, 0.7]},
    "ImageLabel": {"Size": [0, 100, 0, 100]},
    "ImageButton": {"Size": [0, 100, 0, 100]},
    "ViewportFrame": {"Size": [0, 100, 0, 100], "Ambient": [200 / 255] * 3, "LightColor": [140 / 255] * 3,
                      "LightDirection": [-1, -1, -1], "ImageColor3": [1, 1, 1], "ImageTransparency": 0},
    "CanvasGroup": {"Size": [0, 100, 0, 100], "GroupTransparency": 0, "GroupColor3": [1, 1, 1]},
    "ScreenGui": {"Enabled": True, "DisplayOrder": 0, "IgnoreGuiInset": False, "ScreenInsets": "CoreUISafeInsets",
                  "ZIndexBehavior": "Sibling"},
    "UIListLayout": {"FillDirection": "Vertical", "Padding": [0, 0], "SortOrder": "LayoutOrder",
                     "HorizontalAlignment": "Left", "VerticalAlignment": "Top", "Wraps": False,
                     "HorizontalFlex": "None", "VerticalFlex": "None", "ItemLineAlignment": "Automatic"},
    "UIGridLayout": {"CellSize": [0, 100, 0, 100], "CellPadding": [0, 5, 0, 5], "FillDirection": "Horizontal",
                     "FillDirectionMaxCells": 0, "SortOrder": "LayoutOrder", "StartCorner": "TopLeft",
                     "HorizontalAlignment": "Left", "VerticalAlignment": "Top"},
    "UIPadding": {"PaddingTop": [0, 0], "PaddingBottom": [0, 0], "PaddingLeft": [0, 0], "PaddingRight": [0, 0]},
    "UIScale": {"Scale": 1},
    "UIStroke": {"Thickness": 1, "Color": [0, 0, 0], "Transparency": 0, "ApplyStrokeMode": "Contextual", "Enabled": True,
                 "LineJoinMode": "Round"},
    "UICorner": {"CornerRadius": [0, 8]},
    "UIGradient": {"Color": {"cs": [[0, 1, 1, 1], [1, 1, 1, 1]]}, "Transparency": {"ns": [[0, 0, 0], [1, 0, 0]]},
                   "Rotation": 0, "Offset": [0, 0], "Enabled": True},
    "UIAspectRatioConstraint": {"AspectRatio": 1, "AspectType": "FitWithinMaxSize", "DominantAxis": "Width"},
    "UISizeConstraint": {"MinSize": [0, 0], "MaxSize": [math.inf, math.inf]},
    "UITextSizeConstraint": {"MinTextSize": 1, "MaxTextSize": 100},
    "UIFlexItem": {"FlexMode": "None", "GrowRatio": 0, "ShrinkRatio": 0},
}
TEXT_DEFAULTS = {
    "TextSize": 14, "TextColor3": INK27, "TextTransparency": 0, "Font": "Legacy", "TextScaled": False,
    "TextWrapped": False, "TextXAlignment": "Center", "TextYAlignment": "Center", "RichText": False,
    "TextStrokeColor3": [0, 0, 0], "TextStrokeTransparency": 1, "TextTruncate": "None", "LineHeight": 1,
    "MaxVisibleGraphemes": -1,
}
IMAGE_DEFAULTS = {"Image": "", "ImageColor3": [1, 1, 1], "ImageTransparency": 0, "ResampleMode": "Default",
                  "ScaleType": "Stretch"}


class Node:
    __slots__ = ("id", "cls", "name", "raw", "kids", "parent", "vp", "x", "y", "w", "h", "k", "clip", "index",
                 "comps", "guikids", "measured", "content_w", "content_h", "canvas", "text_size", "extra")

    def __init__(self, d, parent, index):
        self.id = d.get("id")
        self.cls = d["c"]
        self.name = d.get("n", "")
        self.raw = d.get("p", {})
        self.parent = parent
        self.vp = d.get("vp")
        self.index = index
        self.kids = [Node(c, self, i) for i, c in enumerate(d.get("k", []))]
        self.x = self.y = self.w = self.h = 0.0
        self.k = 1.0
        self.clip = None
        self.canvas = None
        self.text_size = None
        self.extra = {}
        r = d.get("r")
        self.measured = r is not None  # laid out by the Luau engine (guiengine.luau)
        if r is not None:
            self.x, self.y, self.w, self.h = (float(v or 0) for v in r)
            self.k = float(d.get("sk") or 1)
            cl = d.get("cl")
            self.clip = tuple(cl) if cl else None
            cv = d.get("cv")
            self.canvas = tuple(cv) if cv else None
        self.extra["tx"] = d.get("tx")
        # components (first of each kind wins, like Roblox) and GUI children (Folders flattened)
        self.comps = {}
        for c in self.kids:
            if c.cls not in GUI_OBJECTS and c.cls != "Folder" and c.cls not in self.comps:
                self.comps[c.cls] = c
        self.guikids = []
        for c in self.kids:
            if c.cls in GUI_OBJECTS:
                self.guikids.append(c)
            elif c.cls == "Folder":
                self.guikids.extend(c.flat_gui())

    def flat_gui(self):
        out = []
        for c in self.kids:
            if c.cls in GUI_OBJECTS:
                out.append(c)
            elif c.cls == "Folder":
                out.extend(c.flat_gui())
        return out

    def get(self, key):
        v = self.raw.get(key)
        if v is not None:
            return v
        d = DEFAULTS.get(self.cls)
        if d and key in d:
            return d[key]
        if self.cls in TEXT_CLASSES and key in TEXT_DEFAULTS:
            return TEXT_DEFAULTS[key]
        if self.cls in IMAGE_CLASSES and key in IMAGE_DEFAULTS:
            return IMAGE_DEFAULTS[key]
        if self.cls in GUI_OBJECTS and key in DEFAULTS_COMMON:
            return DEFAULTS_COMMON[key]
        return None

    def comp(self, cls):
        return self.comps.get(cls)

    def visible(self):
        return self.get("Visible") is not False
