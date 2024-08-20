

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef void StreamStateCallback(MediaStream stream);

class Signaling {
  Map<String,dynamic> configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302'
        ]
      }
    ]
  };

// Declaring all the variable that will be used
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  String? roomId;
  String? currentRoomText;
  StreamStateCallback? onAddRemoteStream;

  Future createRoom(RTCVideoRenderer remoteRenderer) async {
// Create a database instance
    FirebaseFirestore db = FirebaseFirestore.instance;

// creating a reference to the document that we'll use to read write and delete data
    DocumentReference roomRef = db.collection('rooms').doc();

    print('Create PeerConnection with configuration: $configuration');

    peerConnection = await createPeerConnection(configuration);

    registerPeerConnectionListeners();

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

// TODO: Code for collecting ICE candidates below
    var callerCandidatesCollection = roomRef.collection('callerCandidates');

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      print("Got candidate : ${candidate.toMap()}");
      callerCandidatesCollection.add(candidate.toMap());
    };

// TODO: Add code for creating a room
    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    Map roomWithOffer = {"offer": offer.toMap()};
    await roomRef.set(roomWithOffer);
    roomId = roomRef.id;

    peerConnection?.onTrack = (RTCTrackEvent event) {
      print('Got remote track: ${event.streams[0]}');

      event.streams[0].getTracks().forEach((track) {
        print('Add a track to the remoteStream $track');
        remoteStream?.addTrack(track);
      });
    };

// TODO: Listening for remote session description below
    roomRef.snapshots().listen((snapshot) async {
      Map data = snapshot.data() as Map;

      if (peerConnection?.getRemoteDescription() != null &&
          data['answer'] != null) {
        var answer = RTCSessionDescription(
            data['answer']['sdp'], data['answer']['type']);

        await peerConnection?.setRemoteDescription(answer);
      }
    });

// TODO: Listen for remote Ice candidates below
    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) async {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          Map data = change.doc.data() as Map;
          await peerConnection?.addCandidate(RTCIceCandidate(
              data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        }
      }
    });

    return roomId!;
  }

  Future joinRoom(String roomId) async {
    FirebaseFirestore db = FirebaseFirestore.instance;
    DocumentReference roomRef = db.collection('rooms').doc('$roomId');
    var roomSnapshot = await roomRef.get();
    print('Got room ${roomSnapshot.exists}');

    if (roomSnapshot.exists) {
      print('Create PeerConnection with configuration: $configuration');
      peerConnection = await createPeerConnection(configuration);

      registerPeerConnectionListeners();

      localStream?.getTracks().forEach((track) {
        peerConnection?.addTrack(track, localStream!);
      });

// TODO: Code for collecting ICE candidates below
      var calleeCandidatesCollection = roomRef.collection('calleeCandidates');

      peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        print("Got callee candidate : ${candidate.toMap()}");
        calleeCandidatesCollection.add(candidate.toMap());
      };

      peerConnection?.onTrack = (RTCTrackEvent event) {
        print('Got remote track: ${event.streams[0]}');
        event.streams[0].getTracks().forEach((track) {
          print('Add a track to the remoteStream: $track');
          remoteStream?.addTrack(track);
        });
      };

// TODO: Code for creating SDP answer below
      var data = roomSnapshot.data() as Map;
      var offer = data['offer'];
      await peerConnection?.setRemoteDescription(
          RTCSessionDescription(offer['sdp'], offer['type']));

      var answer = await peerConnection?.createAnswer();

      await peerConnection?.setLocalDescription(answer!);

      Map<String,dynamic> roomWithAnswer = {
        'answer': {'type': answer?.type, 'sdp': answer?.sdp}
      };

      await roomRef.update(roomWithAnswer);

// TODO: Listening for remote ICE candidates below
      roomRef
          .collection('callerCandidates')
          .snapshots()
          .listen((snapshot) async {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            Map data =
            change.doc.data() as Map;
            await peerConnection?.addCandidate(RTCIceCandidate(
                data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
          }
        }
      });
    }
  }

  Future openUserMedia(
      RTCVideoRenderer localVideo,
      RTCVideoRenderer remoteVideo,
      ) async {
// 1. Create a MediaStream of local user
    var stream = await navigator.mediaDevices.getUserMedia(
      {'video': true, 'audio': true},
    );

// 2. Assign it to local user src object
    localVideo.srcObject = stream;

// 3. Save it to a local variable to make use ot it in class
    localStream = stream;

// 4. Creating a
    remoteVideo.srcObject = await createLocalMediaStream('key');
  }

  Future hangUp(RTCVideoRenderer localVideo) async {
    List tracks = localVideo.srcObject!.getTracks();
    tracks.forEach((track) {
      track.stop();
    });

    if (remoteStream != null) {
      remoteStream!.getTracks().forEach((track) => track.stop());
    }
    if (peerConnection != null) peerConnection!.close();

    if (roomId != null) {
      var db = FirebaseFirestore.instance;
      var roomRef = db.collection('rooms').doc(roomId);
      var calleeCandidates = await roomRef.collection('calleeCandidates').get();
      calleeCandidates.docs.forEach((document) => document.reference.delete());

      var callerCandidates = await roomRef.collection('callerCandidates').get();
      callerCandidates.docs.forEach((document) => document.reference.delete());

      await roomRef.delete();
    }

    localStream!.dispose();
    remoteStream?.dispose();
  }

  void registerPeerConnectionListeners() {
    peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
      print('ICE gathering state changed: $state');
    };

    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      print('Connection state change: $state');
    };

    peerConnection?.onSignalingState = (RTCSignalingState state) {
      print('Signaling state change: $state');
    };

    peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
      print('ICE connection state change: $state');
    };

    peerConnection?.onAddStream = (MediaStream stream) {
      print("Add remote stream");
      onAddRemoteStream?.call(stream);
      remoteStream = stream;
    };
  }
}