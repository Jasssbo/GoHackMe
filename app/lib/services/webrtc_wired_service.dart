import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

// ── ICE configuration ─────────────────────────────────────────────────────

/// STUN + TURN servers for NAT traversal.
///
/// STUN alone fails for symmetric NAT (common on mobile / CGNAT networks).
/// TURN servers relay traffic as a fallback, ensuring connectivity for all
/// NAT types at the cost of slightly higher latency.
///
/// The TURN credentials below are from the community openrelay project
/// (https://www.metered.ca/tools/openrelay/) — free for low-volume use.
/// Replace with a self-hosted coturn instance for production.
const _kIceServers = [
  {
    'urls': [
      'stun:stun.l.google.com:19302',
      'stun:stun1.l.google.com:19302',
    ],
  },
  {
    'urls': ['stun:stun.cloudflare.com:3478'],
  },
  // ── TURN relay fallback (symmetric NAT / CGNAT) ───────────────────────
  {
    'urls': [
      'turn:openrelay.metered.ca:80',
      'turn:openrelay.metered.ca:443',
    ],
    'username': 'openrelayproject',
    'credential': 'openrelayproject',
  },
  {
    'urls': ['turn:openrelay.metered.ca:443?transport=tcp'],
    'username': 'openrelayproject',
    'credential': 'openrelayproject',
  },
];

const _kPcConfig = {
  'iceServers': _kIceServers,
  'sdpSemantics': 'unified-plan',
  // DTLS/SRTP is mandatory in WebRTC — all traffic is end-to-end encrypted.
  'bundlePolicy': 'max-bundle',
  'rtcpMuxPolicy': 'require',
};

// ── WiredPeerConnection ───────────────────────────────────────────────────

/// Wraps a single [RTCPeerConnection] + [RTCDataChannel] pair.
///
/// Security properties enforced here:
/// - Messages larger than [_kMaxMessageBytes] are silently dropped (DoS
///   protection / memory exhaustion prevention).
/// - Rate limiting: more than [_kMaxMsgsPerSecond] messages from a single
///   peer closes the channel (flooding protection).
/// - Player identity is bound once on the first `joinRoom` message — any
///   subsequent attempt to use a different ID is dropped.
class WiredPeerConnection {
  static const _kMaxMessageBytes = 65536; // 64 KB
  static const _kMaxMsgsPerSecond = 10;

  final String sessionId;

  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;

  String? _boundPlayerId; // set once; immutable after first joinRoom
  String? get boundPlayerId => _boundPlayerId;

  bool get isOpen => _channel?.state == RTCDataChannelState.RTCDataChannelOpen;

  // Rate-limiting state
  int _msgCount = 0;
  DateTime _windowStart = DateTime.now();

  final _messageCtrl = StreamController<String>.broadcast();
  final _openCtrl = StreamController<void>.broadcast();
  final _closeCtrl = StreamController<void>.broadcast();

  Stream<String> get messageStream => _messageCtrl.stream;
  Stream<void> get onOpen => _openCtrl.stream;
  Stream<void> get onClose => _closeCtrl.stream;

  WiredPeerConnection(this.sessionId);

  // ── Host side ─────────────────────────────────────────────────────────────

  /// Creates a peer connection and data channel (host role).
  /// Returns the offer SDP after all ICE candidates have been gathered.
  Future<String> createOffer() async {
    await _initPc();

    final dc = await _pc!.createDataChannel(
      'game',
      RTCDataChannelInit()
        ..ordered = true
        ..protocol = 'gohackme',
    );
    _attachDataChannel(dc);

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    return await _gatherIce();
  }

  /// Accepts the guest's answer SDP to complete the offer/answer exchange.
  Future<void> acceptAnswer(String answerSdp) async {
    await _pc!
        .setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
  }

  // ── Client side ───────────────────────────────────────────────────────────

  /// Creates a peer connection and accepts the host's offer.
  /// Returns the answer SDP after all ICE candidates have been gathered.
  /// The caller must also listen to [onOpen] to know when the channel is ready.
  Future<String> createAnswer(String offerSdp) async {
    await _initPc();

    // Guest receives data channel via onDataChannel callback.
    _pc!.onDataChannel = _attachDataChannel;

    await _pc!.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    return await _gatherIce();
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  void send(String json) {
    if (_channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _channel!.send(RTCDataChannelMessage(json));
    }
  }

  /// Bind the first player ID seen — subsequent attempts with a different ID
  /// are ignored (identity spoofing protection).
  bool tryBindPlayerId(String pid) {
    if (_boundPlayerId == null) {
      _boundPlayerId = pid;
      return true;
    }
    return _boundPlayerId == pid;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _initPc() async {
    _pc = await createPeerConnection(_kPcConfig);

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _closeCtrl.add(null);
      }
    };
  }

  void _attachDataChannel(RTCDataChannel dc) {
    _channel = dc;
    dc.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _openCtrl.add(null);
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _closeCtrl.add(null);
      }
    };

    dc.onMessage = (msg) {
      // Security: drop oversized messages.
      if (msg.isBinary) return;
      final text = msg.text;
      if (text.length > _kMaxMessageBytes) return;

      // Security: rate-limit messages per peer.
      final now = DateTime.now();
      if (now.difference(_windowStart).inSeconds >= 1) {
        _windowStart = now;
        _msgCount = 0;
      }
      _msgCount++;
      if (_msgCount > _kMaxMsgsPerSecond) {
        // Flooding detected — close this connection.
        _closeCtrl.add(null);
        dispose();
        return;
      }

      if (!_messageCtrl.isClosed) _messageCtrl.add(text);
    };
  }

  /// Waits until ICE gathering is complete (or times out at 8 s).
  Future<String> _gatherIce() async {
    final completer = Completer<String>();

    Future<void> complete() async {
      if (completer.isCompleted) return;
      final desc = await _pc?.getLocalDescription();
      final sdp = desc?.sdp;
      if (sdp != null && sdp.isNotEmpty) {
        completer.complete(sdp);
      } else {
        completer.completeError(
          StateError('ICE gathering failed: no local description available'),
        );
      }
    }

    _pc!.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        complete();
      }
    };

    // Fallback: if already complete or event never fires.
    // 15 s gives TURN servers time to complete the authenticated round-trip
    // needed to gather relay candidates before the SDP is finalised.
    Future.delayed(const Duration(seconds: 15), complete);

    return completer.future;
  }

  Future<void> dispose() async {
    if (!_messageCtrl.isClosed) await _messageCtrl.close();
    if (!_openCtrl.isClosed) await _openCtrl.close();
    if (!_closeCtrl.isClosed) await _closeCtrl.close();
    await _channel?.close();
    await _pc?.close();
    _channel = null;
    _pc = null;
  }
}
