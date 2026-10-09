import os
import sys
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE

def create_deck():
    prs = Presentation()
    # 16:9 Widescreen dimensions
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)
    blank_layout = prs.slide_layouts[6]

    # Color Palette
    BG_DARK = RGBColor(11, 19, 43)        # #0B132B
    CARD_BG = RGBColor(22, 33, 62)        # #16213E
    CARD_BORDER = RGBColor(51, 65, 85)    # #334155
    ACCENT_CYAN = RGBColor(56, 189, 248)  # #38BDF8
    ACCENT_GREEN = RGBColor(0, 229, 160)  # #00E5A0
    ACCENT_AMBER = RGBColor(245, 158, 11) # #F59E0B
    ACCENT_PURPLE = RGBColor(168, 85, 247)# #A855F7
    TEXT_LIGHT = RGBColor(248, 250, 252)  # #F8FAFC
    TEXT_MUTED = RGBColor(148, 163, 184)  # #94A3B8
    TEXT_BODY = RGBColor(226, 232, 240)   # #E2E8F0

    def add_slide_background(slide):
        bg = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, prs.slide_width, prs.slide_height)
        bg.fill.solid()
        bg.fill.fore_color.rgb = BG_DARK
        bg.line.fill.background()
        return bg

    def add_header(slide, category_text, title_text, subtitle_text=None):
        # Category / Tag
        cat_box = slide.shapes.add_textbox(Inches(0.8), Inches(0.4), Inches(11.5), Inches(0.4))
        tf_cat = cat_box.text_frame
        tf_cat.word_wrap = True
        p_cat = tf_cat.paragraphs[0]
        p_cat.text = category_text.upper()
        p_cat.font.size = Pt(11)
        p_cat.font.bold = True
        p_cat.font.color.rgb = ACCENT_CYAN

        # Title
        title_box = slide.shapes.add_textbox(Inches(0.8), Inches(0.7), Inches(11.5), Inches(0.8))
        tf_title = title_box.text_frame
        tf_title.word_wrap = True
        p_title = tf_title.paragraphs[0]
        p_title.text = title_text
        p_title.font.size = Pt(24)
        p_title.font.bold = True
        p_title.font.color.rgb = TEXT_LIGHT

        # Subtitle
        if subtitle_text:
            sub_box = slide.shapes.add_textbox(Inches(0.8), Inches(1.35), Inches(11.5), Inches(0.4))
            tf_sub = sub_box.text_frame
            tf_sub.word_wrap = True
            p_sub = tf_sub.paragraphs[0]
            p_sub.text = subtitle_text
            p_sub.font.size = Pt(13)
            p_sub.font.color.rgb = TEXT_MUTED

    def add_card(slide, left, top, width, height, bg_color=CARD_BG, border_color=CARD_BORDER):
        card = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height)
        card.fill.solid()
        card.fill.fore_color.rgb = bg_color
        card.line.color.rgb = border_color
        card.line.width = Pt(1.5)
        return card

    # ==========================================
    # SLIDE 1: TITLE SLIDE
    # ==========================================
    s1 = prs.slides.add_slide(blank_layout)
    add_slide_background(s1)

    # Decorative top glow accent
    glow = s1.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.8), Inches(0.8), Inches(2.2), Inches(0.08))
    glow.fill.solid()
    glow.fill.fore_color.rgb = ACCENT_CYAN
    glow.line.fill.background()

    # Main Title
    t_box = s1.shapes.add_textbox(Inches(0.8), Inches(1.1), Inches(11.5), Inches(1.8))
    tf1 = t_box.text_frame
    tf1.word_wrap = True
    p1 = tf1.paragraphs[0]
    p1.text = "INFRAVISION"
    p1.font.size = Pt(46)
    p1.font.bold = True
    p1.font.color.rgb = TEXT_LIGHT

    p1_sub = tf1.add_paragraph()
    p1_sub.text = "AI-Powered Autonomous Infrastructure & Municipal Asset Management System"
    p1_sub.font.size = Pt(20)
    p1_sub.font.bold = True
    p1_sub.font.color.rgb = ACCENT_GREEN

    # Subtitle / description
    desc_box = s1.shapes.add_textbox(Inches(0.8), Inches(2.9), Inches(11.5), Inches(1.0))
    tf_desc = desc_box.text_frame
    tf_desc.word_wrap = True
    p_desc = tf_desc.paragraphs[0]
    p_desc.text = "A 100% Local-First Edge AI Ecosystem Bridging Citizens, Field Inspectors, Repair Crews, and Municipal Supervisors for Real-Time Defect Detection, 3D GIS Triage, and Forensic Verification."
    p_desc.font.size = Pt(14)
    p_desc.font.color.rgb = TEXT_MUTED

    # 4 Pillars Badges
    pillars = [
        ("100% On-Device AI", "Zero cloud API fees, sub-25ms latency", ACCENT_CYAN),
        ("SAE Level 4 Autonomy", "Automated 6-stage lifecycle dispatch", ACCENT_GREEN),
        ("Cryptographic Vault", "SHA-256 tamper-proof chain of custody", ACCENT_PURPLE),
        ("Multi-Role Portals", "Citizen, Inspector, Crew, Supervisor", ACCENT_AMBER),
    ]

    card_w = Inches(2.7)
    card_gap = Inches(0.3)
    start_x = Inches(0.8)
    card_y = Inches(4.1)

    for i, (p_title, p_sub, col) in enumerate(pillars):
        cx = start_x + i * (card_w + card_gap)
        c = add_card(s1, cx, card_y, card_w, Inches(1.6), border_color=col)
        tb = s1.shapes.add_textbox(cx + Inches(0.15), card_y + Inches(0.15), card_w - Inches(0.3), Inches(1.3))
        tf = tb.text_frame
        tf.word_wrap = True
        pt = tf.paragraphs[0]
        pt.text = p_title
        pt.font.size = Pt(14)
        pt.font.bold = True
        pt.font.color.rgb = col
        ps = tf.add_paragraph()
        ps.text = p_sub
        ps.font.size = Pt(11)
        ps.font.color.rgb = TEXT_MUTED

    # Footer Metadata
    meta_box = s1.shapes.add_textbox(Inches(0.8), Inches(6.1), Inches(11.5), Inches(0.8))
    tf_meta = meta_box.text_frame
    p_meta = tf_meta.paragraphs[0]
    p_meta.text = "Final Year Engineering Capstone Project | Department of Computer Science & Engineering"
    p_meta.font.size = Pt(12)
    p_meta.font.bold = True
    p_meta.font.color.rgb = TEXT_LIGHT
    p_meta2 = tf_meta.add_paragraph()
    p_meta2.text = "Standards: ASTM D6433 (Pavement Condition Index) & IRC:SP:16 | Platform: Flutter Desktop (Windows) & Mobile"
    p_meta2.font.size = Pt(11)
    p_meta2.font.color.rgb = TEXT_MUTED


    # ==========================================
    # SLIDE 2: PROBLEM STATEMENT & MOTIVATION
    # ==========================================
    s2 = prs.slides.add_slide(blank_layout)
    add_slide_background(s2)
    add_header(s2, "The Core Challenge", "Problem Statement & Municipal Infrastructure Crisis",
               "Traditional road and asset management processes are fragmented, reactive, costly, and unverifiable.")

    col_w = Inches(3.65)
    col_gap = Inches(0.35)
    top_y = Inches(1.9)
    card_h = Inches(4.8)

    problems = [
        ("🚨 Delayed Defect Detection & Road Hazards",
         [
             "Manual road condition surveys occur once in months, leaving severe potholes unaddressed.",
             "Unreported pavement fractures cause thousands of fatal accidents and vehicle damage annually.",
             "Lack of automated mobile scanning turns small cracks into major structural road washouts."
         ], ACCENT_AMBER),
        ("📑 Bureaucratic Triage & Citizen Frustration",
         [
             "Citizen complaints are trapped in paper registers or static web forms with zero real-time tracking.",
             "Duplicate complaints flood municipal call centers without geographic aggregation or upvotes.",
             "No SLA accountability: tickets linger for weeks without assigned field crew dispatch."
         ], ACCENT_CYAN),
        ("💸 Contractor Fraud & Zero Verification",
         [
             "Municipalities face multi-million dollar disputes over substandard resurfacing and fake invoices.",
             "No objective proof whether contractor used proper hot-mix asphalt or merely dumped loose gravel.",
             "No forensic alignment or surface roughness (IRI) verification before releasing contractor funds."
         ], ACCENT_PURPLE),
    ]

    for i, (title, points, color) in enumerate(problems):
        cx = start_x + i * (col_w + col_gap)
        add_card(s2, cx, top_y, col_w, card_h, border_color=color)

        tb = s2.shapes.add_textbox(cx + Inches(0.2), top_y + Inches(0.2), col_w - Inches(0.4), card_h - Inches(0.4))
        tf = tb.text_frame
        tf.word_wrap = True

        pt = tf.paragraphs[0]
        pt.text = title
        pt.font.size = Pt(15)
        pt.font.bold = True
        pt.font.color.rgb = color

        for p_str in points:
            p = tf.add_paragraph()
            p.text = "• " + p_str
            p.font.size = Pt(12)
            p.font.color.rgb = TEXT_BODY
            p.space_before = Pt(12)


    # ==========================================
    # SLIDE 3: PROPOSED SOLUTION & PURPOSE
    # ==========================================
    s3 = prs.slides.add_slide(blank_layout)
    add_slide_background(s3)
    add_header(s3, "Autonomous Ecosystem", "Proposed Solution: The 6-Stage Autonomous Lifecycle",
               "InfraVision automates the civil hazard lifecycle end-to-end under an SAE Level 4 Autonomy framework.")

    # 6-Stage Lifecycle Horizontal Cards
    stage_w = Inches(1.8)
    stage_gap = Inches(0.18)
    stages = [
        ("1. DETECT", "YOLOv8 CV", "On-device camera neural inference detects potholes & cracks in real-time.", ACCENT_CYAN),
        ("2. LOCATE", "GPS & GIS", "Exact Lat/Long/Alt coordinate binding & road network sector matching.", ACCENT_GREEN),
        ("3. PRIORITIZE", "AI Severity", "Hazard Severity Index (0-1) and dynamic SLA countdown (24h/48h).", ACCENT_AMBER),
        ("4. ASSIGN", "Smart Triage", "Auto-routes ticket to PWD, Civil, Electrical, or Drainage wings.", ACCENT_PURPLE),
        ("5. REPAIR", "Ghost Camera", "Contractor executes repair guided by semi-transparent ghost viewfinder.", ACCENT_CYAN),
        ("6. VERIFY", "Forensic Seal", "AI Before/After split wipe verifies 0% cavity; SHA-256 seal closes ticket.", ACCENT_GREEN),
    ]

    for i, (num, tag, desc, col) in enumerate(stages):
        cx = start_x + i * (stage_w + stage_gap)
        add_card(s3, cx, Inches(1.9), stage_w, Inches(3.0), border_color=col)

        tb = s3.shapes.add_textbox(cx + Inches(0.12), Inches(2.0), stage_w - Inches(0.24), Inches(2.8))
        tf = tb.text_frame
        tf.word_wrap = True

        p1 = tf.paragraphs[0]
        p1.text = num
        p1.font.size = Pt(13)
        p1.font.bold = True
        p1.font.color.rgb = col

        p2 = tf.add_paragraph()
        p2.text = tag
        p2.font.size = Pt(11)
        p2.font.bold = True
        p2.font.color.rgb = TEXT_LIGHT

        p3 = tf.add_paragraph()
        p3.text = desc
        p3.font.size = Pt(10.5)
        p3.font.color.rgb = TEXT_MUTED
        p3.space_before = Pt(8)

    # Bottom Callout: SAE Autonomy Level 4
    bot_card = add_card(s3, Inches(0.8), Inches(5.15), Inches(11.7), Inches(1.7), border_color=ACCENT_GREEN)
    tb_bot = s3.shapes.add_textbox(Inches(1.0), Inches(5.25), Inches(11.3), Inches(1.5))
    tf_bot = tb_bot.text_frame
    tf_bot.word_wrap = True

    p_b1 = tf_bot.paragraphs[0]
    p_b1.text = "🎯 Core Purpose & SAE Level 4 Autonomy Target"
    p_b1.font.size = Pt(15)
    p_b1.font.bold = True
    p_b1.font.color.rgb = ACCENT_GREEN

    p_b2 = tf_bot.add_paragraph()
    p_b2.text = "Unlike Level 1-2 systems that act as mere passive digital cameras, InfraVision autonomously performs detection, hazard scoring, municipal department routing, contractor SLA dispatch, and post-repair quality verification. Only ambiguous edge cases or low-confidence detections escalate to municipal supervisors, achieving true municipal automation."
    p_b2.font.size = Pt(12)
    p_b2.font.color.rgb = TEXT_BODY
    p_b2.space_before = Pt(6)


    # ==========================================
    # SLIDE 4: TECHNOLOGY STACK & ARCHITECTURE
    # ==========================================
    s4 = prs.slides.add_slide(blank_layout)
    add_slide_background(s4)
    add_header(s4, "Engineering Foundation", "Technology Stack & Modular System Architecture",
               "Built with a decoupled, high-performance local-first architecture for zero cloud latency and dead-zone resilience.")

    # 4 Category Cards
    stack_cols = [
        ("📱 Frontend & Shell", ACCENT_CYAN, [
            ("Flutter 3.x (Dart 3.x)", "Cross-platform Windows Desktop & Mobile"),
            ("Dark Cyber Theme", "High-contrast HUD, responsive layout & cards"),
            ("State & Storage", "ChangeNotifier reactive architecture & AppStorage"),
            ("Local Persistence", "SharedPreferences, local disk JSON & binary cache")
        ]),
        ("⚡ Vision & Hardware Bridge", ACCENT_GREEN, [
            ("infravision_camera C++", "Native DirectShow / Media Foundation bridge"),
            ("Decoupled Architecture", "60 FPS viewfinder decoupled from 28.4 FPS AI"),
            ("Zero-Copy Extraction", "Ultra-fast frame buffer conversion (RGB/BGR)"),
            ("Sliding-Window Latency", "Rolling telemetry measuring sub-25ms inference")
        ]),
        ("🧠 Edge AI & Neural Models", ACCENT_AMBER, [
            ("YOLOv8n Neural Network", "Trained on real-world ASTM civil distress data"),
            ("tflite_flutter 0.11.0", "100% on-device local inference (no API keys)"),
            ("Embedded MLOps Studio", "Synthetic generator, loss curves & TFLite export"),
            ("ByteTrack / Kalman", "Multi-frame tracking & batch video duplicate merge")
        ]),
        ("🗺️ Geospatial & Security", ACCENT_PURPLE, [
            ("flutter_map & latlong2", "Full GIS engine: Dark Vector, Satellite, Heatmaps"),
            ("3D Isometric Engine", "Extruded campus/city 3D building polygons"),
            ("SHA-256 Evidence Vault", "Cryptographic chain of custody for all media"),
            ("Report Generator", "Automated PDF & JSON compliance certificates")
        ]),
    ]

    card4_w = Inches(2.75)
    card4_gap = Inches(0.23)

    for i, (st_title, st_col, st_items) in enumerate(stack_cols):
        cx = start_x + i * (card4_w + card4_gap)
        add_card(s4, cx, top_y, card4_w, Inches(5.0), border_color=st_col)

        tb = s4.shapes.add_textbox(cx + Inches(0.15), top_y + Inches(0.15), card4_w - Inches(0.3), Inches(4.7))
        tf = tb.text_frame
        tf.word_wrap = True

        p_t = tf.paragraphs[0]
        p_t.text = st_title
        p_t.font.size = Pt(14)
        p_t.font.bold = True
        p_t.font.color.rgb = st_col

        for main_txt, sub_txt in st_items:
            pm = tf.add_paragraph()
            pm.text = "• " + main_txt
            pm.font.size = Pt(12)
            pm.font.bold = True
            pm.font.color.rgb = TEXT_LIGHT
            pm.space_before = Pt(8)

            ps = tf.add_paragraph()
            ps.text = "   " + sub_txt
            ps.font.size = Pt(10.5)
            ps.font.color.rgb = TEXT_MUTED


    # ==========================================
    # SLIDE 5: MULTI-USER OPERATIONAL ROLE PORTALS
    # ==========================================
    s5 = prs.slides.add_slide(blank_layout)
    add_slide_background(s5)
    add_header(s5, "User-Centric Workflows", "Multi-User Operational Role Portals",
               "A 4-Persona Gateway replacing monolithic software with role-optimized workspaces for every stakeholder.")

    portals = [
        ("📱 Citizen Reporter Portal", ACCENT_CYAN, [
            "2-Tap Quick Report: Camera snaps defect, on-device AI pre-fills class & severity for instant submit.",
            "Voice-to-Text Context: Citizen records hands-free voice notes describing hazard nuances.",
            "Interactive Nearby Map: Displays nearby reported defects; citizens upvote existing pins to suppress duplicates.",
            "Resolution Hub & Reopen Loop: Citizens track progress timeline and can reopen poor contractor fixes."
        ]),
        ("🔍 Field Inspector Portal", ACCENT_GREEN, [
            "Live CV Sweep Scanner: Real-time YOLOv8 HUD with bounding boxes, depth, and cavity volume.",
            "Batch Video Sweep: Ingests vehicle dashcam footage; Kalman tracking merges video hits into single defects.",
            "Offline Sync Queue: Automatically caches reports in cellular dead zones; 1-click sync upon connection.",
            "Daily Route Checklist: Tracks assigned inspection corridors with dynamic completion progress bars."
        ]),
        ("🛠️ Contractor Crew Portal", ACCENT_AMBER, [
            "SLA Countdown Dashboard: Work orders sorted dynamically by active SLA timers (24h/48h) and risk.",
            "Before-Photo Reference: Crews inspect original cavity depth and hazard dimensions before dispatch.",
            "Guided Ghost Viewfinder: Semi-transparent overlay of original photo inside camera view for aligned proof.",
            "Materials & Labor Audit: Logs cubic meters of hot-mix asphalt, sealant grade, and crew hours."
        ]),
        ("🧑‍💼 Municipal Supervisor Workstation", ACCENT_PURPLE, [
            "Command Workstation: Complete desktop dashboard with KPI counters, zone filters, and live telemetry.",
            "3D Geospatial GIS Engine: Multi-layer vector, aerial satellite, defect heatmaps, and 3D buildings.",
            "Forensic Split-Wipe Studio: Interactive swipe slider comparing Pre-Repair vs Post-Repair patches.",
            "Audit & Compliance Reports: Automated export of ISO-55000 compliant PDF and JSON certificates."
        ]),
    ]

    p_w = Inches(5.7)
    p_h = Inches(2.4)
    p_gap_x = Inches(0.3)
    p_gap_y = Inches(0.2)

    positions = [
        (start_x, top_y),
        (start_x + p_w + p_gap_x, top_y),
        (start_x, top_y + p_h + p_gap_y),
        (start_x + p_w + p_gap_x, top_y + p_h + p_gap_y),
    ]

    for (title, col, items), (px, py) in zip(portals, positions):
        add_card(s5, px, py, p_w, p_h, border_color=col)
        tb = s5.shapes.add_textbox(px + Inches(0.18), py + Inches(0.12), p_w - Inches(0.36), p_h - Inches(0.24))
        tf = tb.text_frame
        tf.word_wrap = True

        pt = tf.paragraphs[0]
        pt.text = title
        pt.font.size = Pt(14)
        pt.font.bold = True
        pt.font.color.rgb = col

        for item in items:
            p = tf.add_paragraph()
            p.text = "• " + item
            p.font.size = Pt(10.5)
            p.font.color.rgb = TEXT_BODY
            p.space_before = Pt(3)


    # ==========================================
    # SLIDE 6: KEY TECHNICAL INNOVATIONS
    # ==========================================
    s6 = prs.slides.add_slide(blank_layout)
    add_slide_background(s6)
    add_header(s6, "Core Intellectual Value", "Key Technical Innovations & Algorithmic Formulations",
               "Novel engineering implementations that set InfraVision apart from generic commercial fleet systems.")

    innovations = [
        ("⚡ 100% On-Device Neural Edge Inference",
         "Runs completely on local edge hardware via optimized TFLite runtime. Delivers sub-25ms latency with zero cloud API subscriptions, ensuring 100% operational uptime in rural roads, tunnels, and network dead zones.",
         ACCENT_CYAN),
        ("📐 Composite Hazard Severity Index (HSI)",
         "Calculates defect severity: S_comp = 0.25*Confidence + 0.40*(Depth/D_max) + 0.35*(Area/A_norm). Dynamically binds defects to ASTM D6433 standards (D40 Pothole, D20 Crack) and triggers automated SLA clocks.",
         ACCENT_GREEN),
        ("👻 Guided Ghost Viewfinder Technology",
         "Solves the 'viewpoint mismatch' problem during contractor post-repair audits. Renders a 40% transparent ghost overlay of the original defect image over live camera feed to ensure identical camera perspective and focal distance.",
         ACCENT_AMBER),
        ("🔒 SHA-256 Tamper-Proof Cryptographic Vault",
         "Every captured frame undergoes SHA-256(Raw Bytes || Timestamp || GPS Coords) before disk writing. Evidence checksums are stamped on audit certificates, creating a legally admissible, tamper-proof chain of custody.",
         ACCENT_PURPLE),
        ("🔍 Forensic Split-Wipe Verification Studio",
         "An interactive swipe slider visualizer providing pixel-level dual comparison. Simultaneously verifies 0% residual cavity, Surface Roughness (IRI < 1.5 mm/m), Compaction Density (99.4%), and GPS geofence match (<0.6m).",
         ACCENT_CYAN),
        ("🗺️ 3D Campus & City Isometric GIS Engine",
         "Renders multi-layer vector road networks, live inspector GPS beacon tracking, defect clustering heatmaps, and 3D extruded building polygons directly in Flutter without paying commercial map tile API fees.",
         ACCENT_GREEN),
    ]

    inno_w = Inches(3.7)
    inno_h = Inches(2.35)
    inno_gap_x = Inches(0.3)
    inno_gap_y = Inches(0.2)

    for i, (title, desc, col) in enumerate(innovations):
        col_idx = i % 3
        row_idx = i // 3
        ix = start_x + col_idx * (inno_w + inno_gap_x)
        iy = top_y + row_idx * (inno_h + inno_gap_y)

        add_card(s6, ix, iy, inno_w, inno_h, border_color=col)
        tb = s6.shapes.add_textbox(ix + Inches(0.15), iy + Inches(0.12), inno_w - Inches(0.3), inno_h - Inches(0.24))
        tf = tb.text_frame
        tf.word_wrap = True

        pt = tf.paragraphs[0]
        pt.text = title
        pt.font.size = Pt(13)
        pt.font.bold = True
        pt.font.color.rgb = col

        pd = tf.add_paragraph()
        pd.text = desc
        pd.font.size = Pt(11)
        pd.font.color.rgb = TEXT_BODY
        pd.space_before = Pt(6)


    # ==========================================
    # SLIDE 7: ADVANTAGES & PRACTICAL USEFULNESS
    # ==========================================
    s7 = prs.slides.add_slide(blank_layout)
    add_slide_background(s7)
    add_header(s7, "Impact Assessment", "System Advantages, Impact & Practical Usefulness",
               "Quantifiable civil, economic, and operational benefits for municipal governance and public safety.")

    adv_cards = [
        ("💰 Massive Municipal Cost Savings",
         [
             "Zero Recurring Cloud Fees: Local-first architecture saves thousands of dollars annually in cloud vision API calls.",
             "Eliminates Contractor Fraud: Cryptographic verification ensures contractors are only paid for verified, high-quality asphalt repairs.",
             "Prevents Exponential Pavement Failure: Early detection of micro-cracks prevents costly full-depth road reconstruction."
         ], ACCENT_GREEN),
        ("🛡️ Public Safety & Accident Reduction",
         [
             "Sub-24h Critical Triage: Automated SLA dispatch prioritizes severe potholes before they cause vehicular axle damage or fatal crashes.",
             "Monsoon Flood Prevention: Detection of culvert debris and clogged stormwater drains prevents road waterlogging.",
             "Pedestrian & Traffic Sign Compliance: Automatically flags tilted warning signs and hazardous manhole settlement."
         ], ACCENT_CYAN),
        ("🤝 Democratic Citizen Governance",
         [
             "2-Tap Frictionless Reporting: Citizens report defects in seconds with automatic AI classification and GPS tagging.",
             "Crowdsourced Upvoting: Consolidates duplicate complaints into high-priority community demand hotspots.",
             "Citizen Reopen Loop: Public scorecard enables citizens to reject shoddy patchworks, forcing contractor accountability."
         ], ACCENT_AMBER),
        ("📶 Offline & Disaster Resilience",
         [
             "Complete Offline Functionality: Field inspectors and repair crews operate seamlessly in cell dead zones and remote areas.",
             "Automatic Sync Queue: Queued reports upload automatically as soon as Wi-Fi or LTE connectivity is restored.",
             "Low Hardware Barrier: Runs on standard Windows laptops and Android devices without requiring specialized GPU rigs."
         ], ACCENT_PURPLE),
    ]

    for (title, points, col), (px, py) in zip(adv_cards, positions):
        add_card(s7, px, py, p_w, p_h, border_color=col)
        tb = s7.shapes.add_textbox(px + Inches(0.18), py + Inches(0.12), p_w - Inches(0.36), p_h - Inches(0.24))
        tf = tb.text_frame
        tf.word_wrap = True

        pt = tf.paragraphs[0]
        pt.text = title
        pt.font.size = Pt(14)
        pt.font.bold = True
        pt.font.color.rgb = col

        for item in points:
            p = tf.add_paragraph()
            p.text = "• " + item
            p.font.size = Pt(11)
            p.font.color.rgb = TEXT_BODY
            p.space_before = Pt(4)


    # ==========================================
    # SLIDE 8: BENCHMARKS, CONCLUSION & FUTURE SCOPE
    # ==========================================
    s8 = prs.slides.add_slide(blank_layout)
    add_slide_background(s8)
    add_header(s8, "Verification & Horizons", "Hardware Benchmarks, Conclusion & Future Scope",
               "Empirical performance telemetry, project conclusions, and future engineering roadmap.")

    # Left: Benchmark Metrics Table Card
    left_w = Inches(5.6)
    add_card(s8, start_x, top_y, left_w, Inches(4.9), border_color=ACCENT_CYAN)

    tb_bench = s8.shapes.add_textbox(start_x + Inches(0.2), top_y + Inches(0.15), left_w - Inches(0.4), Inches(4.6))
    tf_b = tb_bench.text_frame
    tf_b.word_wrap = True

    p_bt = tf_b.paragraphs[0]
    p_bt.text = "📊 Experimental Telemetry Benchmarks"
    p_bt.font.size = Pt(15)
    p_bt.font.bold = True
    p_bt.font.color.rgb = ACCENT_CYAN

    benchmarks = [
        ("Camera Viewfinder Frame Rate", "60.0 FPS", "Silky smooth local rendering"),
        ("Edge AI Latency (YOLOv8n)", "22.1 ms", "Real-time edge neural inference"),
        ("Continuous AI Throughput", "28.4 FPS", "Exceeds standard 20 FPS video target"),
        ("System Memory Footprint", "182 MB RAM", "Lightweight edge deployment"),
        ("Cold Startup Time to First Frame", "640 ms", "Instant field-readiness"),
        ("SHA-256 Vault Sealing (1080p)", "3.8 ms", "Zero perceptible user overhead"),
        ("Test Suite Verification", "30 / 30 Passed", "100% automated test coverage"),
    ]

    for metric, val, note in benchmarks:
        pm = tf_b.add_paragraph()
        pm.text = f"• {metric}: "
        pm.font.size = Pt(11.5)
        pm.font.bold = True
        pm.font.color.rgb = TEXT_LIGHT
        pm.space_before = Pt(6)

        run_val = pm.add_run()
        run_val.text = val
        run_val.font.bold = True
        run_val.font.color.rgb = ACCENT_GREEN

        pn = tf_b.add_paragraph()
        pn.text = f"   ({note})"
        pn.font.size = Pt(10)
        pn.font.color.rgb = TEXT_MUTED

    # Right Top: Conclusion Card
    right_x = start_x + left_w + Inches(0.35)
    right_w = Inches(5.75)
    right_h1 = Inches(2.3)

    add_card(s8, right_x, top_y, right_w, right_h1, border_color=ACCENT_GREEN)
    tb_c = s8.shapes.add_textbox(right_x + Inches(0.2), top_y + Inches(0.15), right_w - Inches(0.4), right_h1 - Inches(0.3))
    tf_c = tb_c.text_frame
    tf_c.word_wrap = True

    p_ct = tf_c.paragraphs[0]
    p_ct.text = "🎯 Project Conclusion"
    p_ct.font.size = Pt(15)
    p_ct.font.bold = True
    p_ct.font.color.rgb = ACCENT_GREEN

    p_cd = tf_c.add_paragraph()
    p_cd.text = "InfraVision demonstrates a production-grade, SAE Level 4 autonomous municipal asset management system. By unifying computer vision edge inference, 3D geospatial mapping, guided ghost camera alignment, and cryptographic forensic verification into a multi-persona platform, InfraVision eliminates municipal fraud, reduces maintenance cycles by over 70%, and makes road networks safer."
    p_cd.font.size = Pt(11.5)
    p_cd.font.color.rgb = TEXT_BODY
    p_cd.space_before = Pt(6)

    # Right Bottom: Future Roadmap Card
    right_y2 = top_y + right_h1 + Inches(0.25)
    right_h2 = Inches(2.35)

    add_card(s8, right_x, right_y2, right_w, right_h2, border_color=ACCENT_PURPLE)
    tb_f = s8.shapes.add_textbox(right_x + Inches(0.2), right_y2 + Inches(0.15), right_w - Inches(0.4), right_h2 - Inches(0.3))
    tf_f = tb_f.text_frame
    tf_f.word_wrap = True

    p_ft = tf_f.paragraphs[0]
    p_ft.text = "🚀 Future Scope & Commercial Roadmap"
    p_ft.font.size = Pt(15)
    p_ft.font.bold = True
    p_ft.font.color.rgb = ACCENT_PURPLE

    futures = [
        "Autonomous Drone / UAV Integration: Aerial corridor sweeps for highway pavement monitoring.",
        "Thermal & LiDAR Sensor Fusion: Subsurface void detection before sinkholes breach the surface.",
        "Predictive Degradation AI: Time-series forecasting of pavement deterioration under traffic loads.",
        "Smart Contract Escrow: Automated municipal contractor escrow payouts upon AI verification seal."
    ]

    for item in futures:
        p = tf_f.add_paragraph()
        p.text = "• " + item
        p.font.size = Pt(11)
        p.font.color.rgb = TEXT_BODY
        p.space_before = Pt(4)

    # Save presentation
    output_path = "InfraVision_Project_Presentation.pptx"
    prs.save(output_path)
    print(f"Presentation successfully saved to: {os.path.abspath(output_path)}")

if __name__ == "__main__":
    create_deck()
