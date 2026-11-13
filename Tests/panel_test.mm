// panel_test.mm  (macOS only)
// Loads the built CLAP, opens its panel through the CLAP GUI extension in an
// offscreen window, renders screenshots, drives the controls with synthetic
// mouse events, checks that edits reach the host as gesture/value events,
// tests presets, and closes everything again.
//
//   panel_test <path to the .clap binary> <output dir for PNGs>

#import <Cocoa/Cocoa.h>

#include <clap/clap.h>

#include "Params.h"
#include "Editor.h"

#include <dlfcn.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static int failures = 0;
static void check (bool ok, const char* what)
{
    std::printf ("  %s  %s\n", ok ? "ok  " : "FAIL", what);
    if (! ok) ++failures;
}

static int flushRequests = 0;
static void hpRescan (const clap_host_t*, clap_param_rescan_flags) {}
static void hpClear (const clap_host_t*, clap_id, clap_param_clear_flags) {}
static void hpRequestFlush (const clap_host_t*) { ++flushRequests; }
static const clap_host_params_t hostParams = { hpRescan, hpClear, hpRequestFlush };
static const void* hGetExt (const clap_host_t*, const char* id) { return ! std::strcmp (id, CLAP_EXT_PARAMS) ? &hostParams : nullptr; }
static void hNoop (const clap_host_t*) {}
static const clap_host_t host = { CLAP_VERSION_INIT, nullptr, "panel_test", "TB", "", "1.0", hGetExt, hNoop, hNoop, hNoop };

struct OutEvents
{
    int values = 0, begins = 0, ends = 0;
    clap_output_events_t list;
    OutEvents() { list.ctx = this; list.try_push = &sPush; }
    static bool sPush (const clap_output_events_t* l, const clap_event_header_t* h)
    {
        OutEvents* o = (OutEvents*) l->ctx;
        if (h->type == CLAP_EVENT_PARAM_VALUE) ++o->values;
        if (h->type == CLAP_EVENT_PARAM_GESTURE_BEGIN) ++o->begins;
        if (h->type == CLAP_EVENT_PARAM_GESTURE_END) ++o->ends;
        return true;
    }
};
static uint32_t noEvents (const clap_input_events_t*) { return 0; }
static const clap_event_header_t* noGet (const clap_input_events_t*, uint32_t) { return nullptr; }

static NSData* renderPNG (NSView* v, const std::string& path)
{
    const NSRect b = [v bounds];
    NSBitmapImageRep* rep = [v bitmapImageRepForCachingDisplayInRect: b];
    [v cacheDisplayInRect: b toBitmapImageRep: rep];
    NSData* png = [rep representationUsingType: NSBitmapImageFileTypePNG properties: [NSDictionary dictionary]];
    [png writeToFile: [NSString stringWithUTF8String: path.c_str()] atomically: YES];
    std::printf ("  wrote %s (%lu bytes)\n", path.c_str(), (unsigned long) [png length]);
    return png;
}

static void mouse (NSWindow* w, NSView* v, NSEventType type, NSPoint panelPt, int clicks = 1)
{
    const NSPoint wp = [v convertPoint: panelPt toView: nil];
    NSEvent* e = [NSEvent mouseEventWithType: type location: wp modifierFlags: 0 timestamp: 0
                                windowNumber: [w windowNumber] context: nil eventNumber: 0
                                  clickCount: clicks pressure: 1.0f];
    if (type == NSEventTypeLeftMouseDown) [v mouseDown: e];
    else if (type == NSEventTypeLeftMouseDragged) [v mouseDragged: e];
    else [v mouseUp: e];
}
static void click (NSWindow* w, NSView* v, NSPoint pt, int clicks = 1)
{
    mouse (w, v, NSEventTypeLeftMouseDown, pt, clicks);
    mouse (w, v, NSEventTypeLeftMouseUp, pt, clicks);
}
static void pump (double secs) { [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: secs]]; }

static double val (const clap_plugin_t* p, const clap_plugin_params_t* pp, int id)
{
    double v = -1; pp->get_value (p, (clap_id) id, &v); return v;
}

// One processing block, so queued panel edits reach the "host".
static void processBlock (const clap_plugin_t* p, OutEvents& out)
{
    std::vector<float> l (256, 0.0f), r (256, 0.0f), ol (256), orr (256);
    float* ins[2] = { &l[0], &r[0] };
    float* outs[2] = { &ol[0], &orr[0] };
    clap_audio_buffer_t ib; std::memset (&ib, 0, sizeof (ib)); ib.data32 = ins; ib.channel_count = 2;
    clap_audio_buffer_t ob; std::memset (&ob, 0, sizeof (ob)); ob.data32 = outs; ob.channel_count = 2;
    clap_input_events_t in = { nullptr, noEvents, noGet };
    clap_process_t pr; std::memset (&pr, 0, sizeof (pr));
    pr.steady_time = -1; pr.frames_count = 256;
    pr.audio_inputs = &ib; pr.audio_inputs_count = 1; pr.audio_outputs = &ob; pr.audio_outputs_count = 1;
    pr.in_events = &in; pr.out_events = &out.list;
    p->process (p, &pr);
}

// Does the preset file hold this name line?
static bool fileHasLine (const std::string& path, const char* needle)
{
    bool found = false;
    FILE* nf = std::fopen (path.c_str(), "r");
    if (nf)
    {
        char ln[256];
        while (std::fgets (ln, sizeof (ln), nf)) if (std::strstr (ln, needle)) found = true;
        std::fclose (nf);
    }
    return found;
}

int main (int argc, char** argv)
{
    if (argc < 3) { std::printf ("usage: %s <clap binary> <png dir>\n", argv[0]); return 2; }
    setvbuf (stdout, 0, _IONBF, 0);
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    const std::string dir = argv[2];

    const std::string presetFile = dir + "/test_presets/Presets.txt";
    setenv ("TBVS_PRESET_FILE", presetFile.c_str(), 1);
    std::remove (presetFile.c_str());

    void* lib = dlopen (argv[1], RTLD_NOW | RTLD_LOCAL);
    if (! lib) { std::printf ("dlopen failed: %s\n", dlerror()); return 1; }
    const clap_plugin_entry_t* entry = (const clap_plugin_entry_t*) dlsym (lib, "clap_entry");
    entry->init (argv[1]);
    const clap_plugin_factory_t* f = (const clap_plugin_factory_t*) entry->get_factory (CLAP_PLUGIN_FACTORY_ID);
    const clap_plugin_t* p = f->create_plugin (f, &host, f->get_plugin_descriptor (f, 0)->id);
    p->init (p);
    p->activate (p, 44100.0, 1, 4096);
    p->start_processing (p);
    const clap_plugin_params_t* pp = (const clap_plugin_params_t*) p->get_extension (p, CLAP_EXT_PARAMS);

    std::printf ("Panel\n");
    const clap_plugin_gui_t* gui = (const clap_plugin_gui_t*) p->get_extension (p, CLAP_EXT_GUI);
    check (gui && gui->is_api_supported (p, CLAP_WINDOW_API_COCOA, false), "supports an embedded Cocoa panel");
    uint32_t w = 0, h = 0;
    check (gui->create (p, CLAP_WINDOW_API_COCOA, false) && gui->get_size (p, &w, &h) && w == 1200 && h == 330, "panel size 1200 x 330");

    NSWindow* win = [[NSWindow alloc] initWithContentRect: NSMakeRect (0, 0, w, h) styleMask: NSWindowStyleMaskBorderless
                                                  backing: NSBackingStoreBuffered defer: NO];
    NSView* parent = [win contentView];
    clap_window_t cw; cw.api = CLAP_WINDOW_API_COCOA; cw.cocoa = parent;
    check (gui->set_parent (p, &cw) && gui->show (p), "panel attaches to the host's view");
    check ([[parent subviews] count] == 1, "panel view added");
    NSView* panel = [[parent subviews] count] ? [[parent subviews] objectAtIndex: 0] : nil;
    if (! panel) return 1;
    NSData* pngDefault = renderPNG (panel, dir + "/panel_default.png");
    check ([pngDefault length] > 10000, "panel renders");

    std::printf ("\nControls\n");
    OutEvents out;
    const double g0 = val (p, pp, tbvs::kCh2Gain);
    flushRequests = 0;
    mouse (win, panel, NSEventTypeLeftMouseDown,    NSMakePoint (393, 112));
    mouse (win, panel, NSEventTypeLeftMouseDragged, NSMakePoint (393, 87));
    mouse (win, panel, NSEventTypeLeftMouseDragged, NSMakePoint (393, 62));
    mouse (win, panel, NSEventTypeLeftMouseUp,      NSMakePoint (393, 62));
    const double g1 = val (p, pp, tbvs::kCh2Gain);
    std::printf ("  Gain %.2f -> %.2f\n", g0, g1);
    check (std::fabs (g1 - (g0 + 0.25)) < 0.02, "dragging a knob up turns it up");
    check (flushRequests > 0, "the host is asked to collect the edit");
    processBlock (p, out);
    check (out.begins == 1 && out.ends == 1 && out.values >= 1, "edit reaches the host as begin / value / end");

    click (win, panel, NSMakePoint (393, 112), 2);
    check (std::fabs (val (p, pp, tbvs::kCh2Gain) - tbvs::kDefaults[tbvs::kCh2Gain]) < 1e-6, "double-click resets a knob");
    click (win, panel, NSMakePoint (170, 196));
    check (val (p, pp, tbvs::kCh1Reverb) == 1.0, "Ch 1 Reverb rocker switches on");
    click (win, panel, NSMakePoint (170, 214));
    check (val (p, pp, tbvs::kCh1Reverb) == 0.0, "and off again");
    const double vz = val (p, pp, tbvs::kVoice);
    click (win, panel, NSMakePoint (845, 112));
    check (val (p, pp, tbvs::kVoice) != vz, "Voice selector changes position");
    click (win, panel, NSMakePoint (199, 296));
    check (val (p, pp, tbvs::kChannel) == 2.0, "Channel slide switch to 1+2");
    click (win, panel, NSMakePoint (141, 296));
    check (val (p, pp, tbvs::kChannel) == 0.0, "Channel slide switch to 1");
    click (win, panel, NSMakePoint (330, 306));
    check (val (p, pp, tbvs::kSpeaker) == 0.0, "Speaker rocker switches off");

    std::printf ("\nPresets\n");
    #define SLOT(k) NSMakePoint (672.0 + (k) * 27.0 + 12.0, 296.0)
    // Set two values the way a host would (flush), then save to slot 3
    {
        clap_event_param_value_t ev[2];
        std::memset (ev, 0, sizeof (ev));
        for (int k = 0; k < 2; ++k)
        {
            ev[k].header.size = sizeof (ev[k]); ev[k].header.space_id = CLAP_CORE_EVENT_SPACE_ID;
            ev[k].header.type = CLAP_EVENT_PARAM_VALUE; ev[k].note_id = -1; ev[k].port_index = -1; ev[k].channel = -1; ev[k].key = -1;
        }
        ev[0].param_id = tbvs::kCh2Gain; ev[0].value = 0.3;
        ev[1].param_id = tbvs::kValveSound; ev[1].value = 1.0;
        struct L { static uint32_t size (const clap_input_events_t*) { return 2; }
                   static const clap_event_header_t* get (const clap_input_events_t* l, uint32_t i) { return &((clap_event_param_value_t*) l->ctx)[i].header; } };
        clap_input_events_t in = { ev, L::size, L::get };
        OutEvents o; pp->flush (p, &in, &o.list);
    }
    pump (0.1);
    click (win, panel, NSMakePoint (635, 296));   // SAVE
    click (win, panel, SLOT (2));                  // slot 3
    FILE* pf = std::fopen (presetFile.c_str(), "r");
    check (pf != nullptr, "SAVE then a slot writes the preset file");
    if (pf) std::fclose (pf);

    // Saving opens a name box over the readout
    NSTextField* field = nil;
    for (NSView* sv in [panel subviews]) if ([sv isKindOfClass: [NSTextField class]]) field = (NSTextField*) sv;
    check (field != nil, "saving opens a box to name the preset");
    renderPNG (panel, dir + "/panel_naming.png");
    if (field)
    {
        [field setStringValue: @"A forty character preset name for tests"];   // 40 characters
        [(id) panel controlTextDidChange: nil];
        renderPNG (panel, dir + "/panel_naming_long.png");
        [field setStringValue: @"Big slow flange"];
        [field sendAction: [field action] to: [field target]];       // Return
        pump (0.2);
    }
    check (fileHasLine (presetFile, "name 3: Big slow flange"), "Return saves the name with the preset");
    bool gone = true;
    for (NSView* sv in [panel subviews]) if ([sv isKindOfClass: [NSTextField class]]) gone = false;
    check (gone, "and the name box goes away");
    renderPNG (panel, dir + "/panel_preset_saved.png");

    {
        clap_event_param_value_t ev; std::memset (&ev, 0, sizeof (ev));
        ev.header.size = sizeof (ev); ev.header.space_id = CLAP_CORE_EVENT_SPACE_ID; ev.header.type = CLAP_EVENT_PARAM_VALUE;
        ev.param_id = tbvs::kCh2Gain; ev.value = 0.9; ev.note_id = -1; ev.port_index = -1; ev.channel = -1; ev.key = -1;
        struct L { static uint32_t size (const clap_input_events_t*) { return 1; }
                   static const clap_event_header_t* get (const clap_input_events_t* l, uint32_t) { return (const clap_event_header_t*) l->ctx; } };
        clap_input_events_t in = { &ev, L::size, L::get };
        OutEvents o; pp->flush (p, &in, &o.list);
    }
    OutEvents rec;
    click (win, panel, SLOT (2));
    processBlock (p, rec);
    check (std::fabs (val (p, pp, tbvs::kCh2Gain) - 0.3) < 1e-5 && val (p, pp, tbvs::kValveSound) == 1.0,
           "clicking the slot recalls the saved settings");
    check (rec.values >= tbvs::kNumParams, "recall tells the host about every parameter");
    renderPNG (panel, dir + "/panel_preset_loaded.png");

    // Clicking the readout while the preset is in use renames it; Esc keeps the old name
    click (win, panel, NSMakePoint (1038.5, 296));
    field = nil;
    for (NSView* sv in [panel subviews]) if ([sv isKindOfClass: [NSTextField class]]) field = (NSTextField*) sv;
    check (field != nil && [[field stringValue] isEqualToString: @"Big slow flange"], "clicking the readout opens the name to edit");
    if (field)
    {
        [field setStringValue: @"Something else"];
        [(id) panel control: field textView: nil doCommandBySelector: @selector (cancelOperation:)];   // Esc
        pump (0.2);
    }
    check (fileHasLine (presetFile, "name 3: Big slow flange"), "Esc keeps the old name");
    const double before = val (p, pp, tbvs::kCh2Gain);
    click (win, panel, SLOT (5));
    check (val (p, pp, tbvs::kCh2Gain) == before, "an empty slot changes nothing");

    std::printf ("\nHost changes show on the panel\n");
    {
        clap_event_param_value_t ev; std::memset (&ev, 0, sizeof (ev));
        ev.header.size = sizeof (ev); ev.header.space_id = CLAP_CORE_EVENT_SPACE_ID; ev.header.type = CLAP_EVENT_PARAM_VALUE;
        ev.param_id = tbvs::kMasterVolume; ev.value = 0.9; ev.note_id = -1; ev.port_index = -1; ev.channel = -1; ev.key = -1;
        struct L { static uint32_t size (const clap_input_events_t*) { return 1; }
                   static const clap_event_header_t* get (const clap_input_events_t* l, uint32_t) { return (const clap_event_header_t*) l->ctx; } };
        clap_input_events_t in = { &ev, L::size, L::get };
        OutEvents o; pp->flush (p, &in, &o.list);
    }
    pump (0.3);
    NSData* pngAfter = renderPNG (panel, dir + "/panel_changed.png");
    check (! [pngAfter isEqualToData: pngDefault], "panel redraws after host changes");

    std::printf ("\nClose\n");
    gui->hide (p);
    gui->destroy (p);
    check ([[parent subviews] count] == 0, "destroying the GUI removes the panel");
    check (gui->create (p, CLAP_WINDOW_API_COCOA, false) && gui->set_parent (p, &cw) && [[parent subviews] count] == 1, "reopens");
    renderPNG ([[parent subviews] objectAtIndex: 0], dir + "/panel_showcase.png");
    gui->destroy (p);
    p->stop_processing (p);
    p->deactivate (p);
    p->destroy (p);
    entry->deinit();
    [win release];
    [pool release];
    dlclose (lib);

    std::printf ("\n%s (%d failure%s)\n", failures ? "FAILED" : "ALL PANEL CHECKS PASSED", failures, failures == 1 ? "" : "s");
    return failures ? 1 : 0;
}
