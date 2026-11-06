import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/local_data.dart';
import '../theme/app_theme.dart';

/// Real slippy map for DPI points.
///
/// This replaces the schematic `CustomPainter` the first iteration shipped (and
/// restores the `FlutterMap` + `MarkerLayer` that the prototype's
/// `PetaDpiScreen` used). It keeps the same constructor as the painter it
/// replaced, so every caller — Peta, Navigasi, the point sheet — is unchanged.
///
/// Tiles come from OpenStreetMap, which needs a signal. At sea a phone is often
/// offline, so the map is built to degrade rather than fail:
///  * an Esri street-map layer sits underneath as a second source,
///  * markers, track, bearing line and the vessel dot are drawn by Flutter, not
///    fetched, so they survive with no tiles at all,
///  * the sea keeps the app's own background colour, so a blank tile area still
///    reads as water instead of a grey void.
class SeaMap extends StatefulWidget {
  const SeaMap({
    super.key,
    required this.points,
    required this.userLat,
    required this.userLon,
    this.ownSpots = const <OwnSpot>[],
    this.track = const <List<double>>[],
    this.selected,
    this.bearingTo,
    this.home,
    this.onMarkerTap,
    this.onOwnSpotTap,
    this.interactive = false,
    this.height,
  });

  final List<DpiPoint> points;
  final double userLat;
  final double userLon;

  /// MAP-6: the sailor's own spots, drawn as diamonds so they are never
  /// mistaken for a numbered DPI point.
  final List<OwnSpot> ownSpots;

  final List<List<double>> track;
  final DpiPoint? selected;
  final DpiPoint? bearingTo;
  final List<double>? home;
  final ValueChanged<DpiPoint>? onMarkerTap;
  final ValueChanged<OwnSpot>? onOwnSpotTap;

  /// False on the dashboard's small preview card: panning there would steal the
  /// scroll gesture. The full Peta screen passes true.
  final bool interactive;

  /// Explicit height; when null the map fills its parent.
  final double? height;

  @override
  State<SeaMap> createState() => _SeaMapState();
}

class _SeaMapState extends State<SeaMap> {
  final MapController _controller = MapController();
  bool _ready = false;

  /// Once the sailor pans away, the camera must stop re-centring on every GPS
  /// tick — otherwise the map fights their finger.
  bool _userMoved = false;

  /// Where the camera was last put, so a duplicate tick can be skipped.
  LatLng? _lastCentre;

  @override
  void didUpdateWidget(covariant SeaMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ready || _userMoved) return;
    final bool posChanged = oldWidget.userLat != widget.userLat ||
        oldWidget.userLon != widget.userLon;
    final LatLng next = LatLng(widget.userLat, widget.userLon);
    if (posChanged && next != _lastCentre) {
      _lastCentre = next;
      _controller.move(next, _controller.camera.zoom);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Centre and zoom that keep every marker, the vessel and the port on screen.
  (LatLng, double) _initialCamera(BuildContext context) {
    final List<LatLng> all = <LatLng>[
      LatLng(widget.userLat, widget.userLon),
      if (widget.home != null) LatLng(widget.home![0], widget.home![1]),
      for (final DpiPoint p in widget.points.take(80)) LatLng(p.lat, p.lon),
    ];
    _lastCentre = all.first;

    if (all.length < 2) {
      return (all.first, 11);
    }

    // Fit the bounding box, then derive a Web-Mercator zoom from the measured
    // height so the result is stable across the card and full-screen variants.
    double minLat = all.first.latitude, maxLat = all.first.latitude;
    double minLon = all.first.longitude, maxLon = all.first.longitude;
    for (final LatLng p in all) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }
    final LatLng centre = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);

    // Pad the span so markers do not sit on the edge. The floor stops a single
    // cluster of near-identical points from zooming to street level.
    final double spanLat = math.max((maxLat - minLat) * 1.35, 0.35);
    final double spanLon = math.max((maxLon - minLon) * 1.35, 0.35);

    final Size size = MediaQuery.sizeOf(context);
    final double h = widget.height ?? size.height * 0.6;
    final double w = size.width;

    // Web Mercator: one tile covers 360° of longitude at zoom 0, 256 px wide.
    final double zoomLon = math.log(w * 360 / (spanLon * 256)) / math.ln2;
    final double zoomLat = math.log(h * 360 / (spanLat * 256)) / math.ln2;
    final double zoom = math.min(zoomLon, zoomLat).clamp(3.5, 13.0);

    return (centre, zoom);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final (LatLng centre, double zoom) = _initialCamera(context);

    final Widget map = FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: centre,
        initialZoom: zoom,
        minZoom: 3,
        maxZoom: 17,
        backgroundColor: c.mapBg,
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
        onMapReady: () {
          _ready = true;
        },
        onPositionChanged: (MapCamera camera, bool hasGesture) {
          if (hasGesture) _userMoved = true;
        },
      ),
      children: <Widget>[
        // Second source drawn underneath: shows through wherever OSM has no
        // tile, so an offline or rate-limited host still leaves a usable chart.
        TileLayer(
          urlTemplate: MapConfig.tileFallbackUrl,
          userAgentPackageName: 'id.fishguard.fishguard_app',
          maxNativeZoom: 18,
        ),
        TileLayer(
          urlTemplate: MapConfig.tileUrl,
          userAgentPackageName: 'id.fishguard.fishguard_app',
          maxNativeZoom: 18,
          // A missing tile at sea is expected; the sea colour shows through.
          errorTileCallback: (TileImage _, Object _, StackTrace? _) {},
        ),
        if (widget.track.length > 1)
          PolylineLayer<Object>(
            polylines: <Polyline<Object>>[
              Polyline<Object>(
                points: <LatLng>[
                  for (final List<double> t in widget.track) LatLng(t[0], t[1]),
                ],
                color: c.primary.withValues(alpha: 0.6),
                strokeWidth: 3,
              ),
            ],
          ),
        if (widget.bearingTo != null)
          PolylineLayer<Object>(
            polylines: <Polyline<Object>>[
              Polyline<Object>(
                points: <LatLng>[
                  LatLng(widget.userLat, widget.userLon),
                  LatLng(widget.bearingTo!.lat, widget.bearingTo!.lon),
                ],
                color: c.primary,
                strokeWidth: 2.5,
                pattern: StrokePattern.dashed(segments: <double>[10, 7]),
              ),
            ],
          ),
        if (widget.home != null)
          MarkerLayer(
            markers: <Marker>[
              Marker(
                point: LatLng(widget.home![0], widget.home![1]),
                width: 26,
                height: 26,
                child: _PortMarker(color: c.warning),
              ),
            ],
          ),
        if (widget.ownSpots.isNotEmpty)
          MarkerLayer(
            markers: <Marker>[
              for (final OwnSpot s in widget.ownSpots)
                Marker(
                  point: LatLng(s.lat, s.lon),
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  child: _OwnSpotMarker(
                    color: c.accent,
                    onTap: widget.onOwnSpotTap == null
                        ? null
                        : () => widget.onOwnSpotTap!(s),
                  ),
                ),
            ],
          ),
        MarkerLayer(
          markers: <Marker>[
            for (final DpiPoint p in widget.points)
              Marker(
                point: LatLng(p.lat, p.lon),
                width: 34,
                height: 34,
                alignment: Alignment.center,
                child: _DpiMarker(
                  nomor: p.nomor,
                  color: p.onLand ? c.textMuted : c.accent,
                  emphasized: (widget.selected?.nomor == p.nomor &&
                          widget.selected?.wpp == p.wpp) ||
                      (widget.bearingTo?.nomor == p.nomor &&
                          widget.bearingTo?.wpp == p.wpp),
                  ringColor: c.primary,
                  onLand: p.onLand,
                  onTap: widget.onMarkerTap == null
                      ? null
                      : () => widget.onMarkerTap!(p),
                ),
              ),
          ],
        ),
        MarkerLayer(
          markers: <Marker>[
            Marker(
              point: LatLng(widget.userLat, widget.userLon),
              width: 30,
              height: 30,
              child: _VesselMarker(color: c.primary),
            ),
          ],
        ),
        // Attribution, required by the OSM tile policy.
        const Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.all(3),
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0x99000000)),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text(
                  '© OpenStreetMap',
                  style: TextStyle(fontSize: 9, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.height != null) {
      return SizedBox(height: widget.height, child: map);
    }
    return map;
  }
}

/// Numbered badge, matching the printed KKP table.
class _DpiMarker extends StatelessWidget {
  const _DpiMarker({
    required this.nomor,
    required this.color,
    required this.emphasized,
    required this.ringColor,
    this.onLand = false,
    this.onTap,
  });

  final int nomor;
  final Color color;
  final bool emphasized;
  final Color ringColor;

  /// KKP printed this coordinate inland. The marker keeps its number — the
  /// table says what it says — but is drawn hollow and struck through so it
  /// can never be mistaken for water worth sailing to.
  final bool onLand;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double d = emphasized ? 30 : 24;
    final Color fill = onLand ? Colors.transparent : color;
    final Color stroke = onLand ? color : (emphasized ? ringColor : Colors.white);
    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(
                  color: stroke,
                  width: onLand ? 2 : (emphasized ? 2.5 : 1.5),
                ),
                boxShadow: onLand
                    ? null
                    : <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              alignment: Alignment.center,
              child: Text(
                '$nomor',
                style: TextStyle(
                  color: onLand ? color : Colors.white,
                  fontSize: emphasized ? 12 : 10,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            if (onLand)
              Transform.rotate(
                angle: -math.pi / 4,
                child: Container(
                  width: d * 0.8,
                  height: 1.6,
                  color: color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VesselMarker extends StatelessWidget {
  const _VesselMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 8,
              spreadRadius: 3,
            ),
          ],
        ),
      ),
    );
  }
}

class _PortMarker extends StatelessWidget {
  const _PortMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

/// MAP-6: the sailor's own spot. A green diamond rather than a numbered
/// circle, so a glance at the chart never confuses "I caught fish here" with
/// "the ministry recommends this square today".
class _OwnSpotMarker extends StatelessWidget {
  const _OwnSpotMarker({required this.color, this.onTap});

  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.white, width: 1.8),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
