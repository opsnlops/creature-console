//
// DO NOT EDIT.
//
// Generated by the protocol buffer compiler.
// Source: messaging/server.proto
//

//
// Copyright 2018, gRPC Authors All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
import GRPC
import NIO
import NIOConcurrencyHelpers
import SwiftProtobuf


/// Usage: instantiate `Server_CreatureServerClient`, then call methods of this protocol to make API calls.
public protocol Server_CreatureServerClientProtocol: GRPCClient {
  var serviceName: String { get }
  var interceptors: Server_CreatureServerClientInterceptorFactoryProtocol? { get }

  func getCreature(
    _ request: Server_CreatureId,
    callOptions: CallOptions?
  ) -> UnaryCall<Server_CreatureId, Server_Creature>

  func getAllCreatures(
    _ request: Server_CreatureFilter,
    callOptions: CallOptions?
  ) -> UnaryCall<Server_CreatureFilter, Server_GetAllCreaturesResponse>

  func createCreature(
    _ request: Server_Creature,
    callOptions: CallOptions?
  ) -> UnaryCall<Server_Creature, Server_DatabaseInfo>

  func updateCreature(
    _ request: Server_Creature,
    callOptions: CallOptions?
  ) -> UnaryCall<Server_Creature, Server_DatabaseInfo>

  func streamLogs(
    _ request: Server_LogFilter,
    callOptions: CallOptions?,
    handler: @escaping (Server_LogItem) -> Void
  ) -> ServerStreamingCall<Server_LogFilter, Server_LogItem>

  func searchCreatures(
    _ request: Server_CreatureName,
    callOptions: CallOptions?
  ) -> UnaryCall<Server_CreatureName, Server_Creature>

  func listCreatures(
    _ request: Server_CreatureFilter,
    callOptions: CallOptions?
  ) -> UnaryCall<Server_CreatureFilter, Server_ListCreaturesResponse>

  func streamFrames(
    callOptions: CallOptions?
  ) -> ClientStreamingCall<Server_Frame, Server_FrameResponse>

  func getServerStatus(
    _ request: SwiftProtobuf.Google_Protobuf_Empty,
    callOptions: CallOptions?
  ) -> UnaryCall<SwiftProtobuf.Google_Protobuf_Empty, Server_ServerStatus>

  func createAnimation(
    _ request: Server_Animation,
    callOptions: CallOptions?
  ) -> UnaryCall<Server_Animation, Server_DatabaseInfo>

  func listAnimations(
    _ request: Server_AnimationFilter,
    callOptions: CallOptions?
  ) -> UnaryCall<Server_AnimationFilter, Server_ListAnimationsResponse>

  func getAnimation(
    _ request: Server_AnimationId,
    callOptions: CallOptions?
  ) -> UnaryCall<Server_AnimationId, Server_Animation>
}

extension Server_CreatureServerClientProtocol {
  public var serviceName: String {
    return "server.CreatureServer"
  }

  /// Fetches one from the database
  ///
  /// - Parameters:
  ///   - request: Request to send to GetCreature.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func getCreature(
    _ request: Server_CreatureId,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Server_CreatureId, Server_Creature> {
    return self.makeUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.getCreature.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetCreatureInterceptors() ?? []
    )
  }

  /// Get all of them
  ///
  /// - Parameters:
  ///   - request: Request to send to GetAllCreatures.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func getAllCreatures(
    _ request: Server_CreatureFilter,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Server_CreatureFilter, Server_GetAllCreaturesResponse> {
    return self.makeUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.getAllCreatures.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetAllCreaturesInterceptors() ?? []
    )
  }

  /// Create a new creature in the database
  ///
  /// - Parameters:
  ///   - request: Request to send to CreateCreature.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func createCreature(
    _ request: Server_Creature,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Server_Creature, Server_DatabaseInfo> {
    return self.makeUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.createCreature.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeCreateCreatureInterceptors() ?? []
    )
  }

  /// Update an existing creature in the database
  ///
  /// - Parameters:
  ///   - request: Request to send to UpdateCreature.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func updateCreature(
    _ request: Server_Creature,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Server_Creature, Server_DatabaseInfo> {
    return self.makeUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.updateCreature.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeUpdateCreatureInterceptors() ?? []
    )
  }

  /// Stream log messages from the server
  ///
  /// - Parameters:
  ///   - request: Request to send to StreamLogs.
  ///   - callOptions: Call options.
  ///   - handler: A closure called when each response is received from the server.
  /// - Returns: A `ServerStreamingCall` with futures for the metadata and status.
  public func streamLogs(
    _ request: Server_LogFilter,
    callOptions: CallOptions? = nil,
    handler: @escaping (Server_LogItem) -> Void
  ) -> ServerStreamingCall<Server_LogFilter, Server_LogItem> {
    return self.makeServerStreamingCall(
      path: Server_CreatureServerClientMetadata.Methods.streamLogs.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeStreamLogsInterceptors() ?? [],
      handler: handler
    )
  }

  /// Search for a Creature by name
  ///
  /// - Parameters:
  ///   - request: Request to send to SearchCreatures.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func searchCreatures(
    _ request: Server_CreatureName,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Server_CreatureName, Server_Creature> {
    return self.makeUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.searchCreatures.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeSearchCreaturesInterceptors() ?? []
    )
  }

  /// Unary call to ListCreatures
  ///
  /// - Parameters:
  ///   - request: Request to send to ListCreatures.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func listCreatures(
    _ request: Server_CreatureFilter,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Server_CreatureFilter, Server_ListCreaturesResponse> {
    return self.makeUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.listCreatures.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeListCreaturesInterceptors() ?? []
    )
  }

  /// Stream frames from the client to a Creature. Used for real time control, if
  /// that's something I want to do.
  ///
  /// Callers should use the `send` method on the returned object to send messages
  /// to the server. The caller should send an `.end` after the final message has been sent.
  ///
  /// - Parameters:
  ///   - callOptions: Call options.
  /// - Returns: A `ClientStreamingCall` with futures for the metadata, status and response.
  public func streamFrames(
    callOptions: CallOptions? = nil
  ) -> ClientStreamingCall<Server_Frame, Server_FrameResponse> {
    return self.makeClientStreamingCall(
      path: Server_CreatureServerClientMetadata.Methods.streamFrames.path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeStreamFramesInterceptors() ?? []
    )
  }

  /// Unary call to GetServerStatus
  ///
  /// - Parameters:
  ///   - request: Request to send to GetServerStatus.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func getServerStatus(
    _ request: SwiftProtobuf.Google_Protobuf_Empty,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<SwiftProtobuf.Google_Protobuf_Empty, Server_ServerStatus> {
    return self.makeUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.getServerStatus.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetServerStatusInterceptors() ?? []
    )
  }

  ///*
  ///Save a new animation in the database
  ///
  ///Defined in server/animation/database.cpp
  ///
  /// - Parameters:
  ///   - request: Request to send to CreateAnimation.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func createAnimation(
    _ request: Server_Animation,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Server_Animation, Server_DatabaseInfo> {
    return self.makeUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.createAnimation.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeCreateAnimationInterceptors() ?? []
    )
  }

  ///*
  ///Returns a list of the animations that match a filter
  ///
  /// - Parameters:
  ///   - request: Request to send to ListAnimations.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func listAnimations(
    _ request: Server_AnimationFilter,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Server_AnimationFilter, Server_ListAnimationsResponse> {
    return self.makeUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.listAnimations.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeListAnimationsInterceptors() ?? []
    )
  }

  /// Unary call to GetAnimation
  ///
  /// - Parameters:
  ///   - request: Request to send to GetAnimation.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func getAnimation(
    _ request: Server_AnimationId,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Server_AnimationId, Server_Animation> {
    return self.makeUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.getAnimation.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetAnimationInterceptors() ?? []
    )
  }
}

#if compiler(>=5.6)
@available(*, deprecated)
extension Server_CreatureServerClient: @unchecked Sendable {}
#endif // compiler(>=5.6)

@available(*, deprecated, renamed: "Server_CreatureServerNIOClient")
public final class Server_CreatureServerClient: Server_CreatureServerClientProtocol {
  private let lock = Lock()
  private var _defaultCallOptions: CallOptions
  private var _interceptors: Server_CreatureServerClientInterceptorFactoryProtocol?
  public let channel: GRPCChannel
  public var defaultCallOptions: CallOptions {
    get { self.lock.withLock { return self._defaultCallOptions } }
    set { self.lock.withLockVoid { self._defaultCallOptions = newValue } }
  }
  public var interceptors: Server_CreatureServerClientInterceptorFactoryProtocol? {
    get { self.lock.withLock { return self._interceptors } }
    set { self.lock.withLockVoid { self._interceptors = newValue } }
  }

  /// Creates a client for the server.CreatureServer service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Server_CreatureServerClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self._defaultCallOptions = defaultCallOptions
    self._interceptors = interceptors
  }
}

public struct Server_CreatureServerNIOClient: Server_CreatureServerClientProtocol {
  public var channel: GRPCChannel
  public var defaultCallOptions: CallOptions
  public var interceptors: Server_CreatureServerClientInterceptorFactoryProtocol?

  /// Creates a client for the server.CreatureServer service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Server_CreatureServerClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

#if compiler(>=5.6)
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol Server_CreatureServerAsyncClientProtocol: GRPCClient {
  static var serviceDescriptor: GRPCServiceDescriptor { get }
  var interceptors: Server_CreatureServerClientInterceptorFactoryProtocol? { get }

  func makeGetCreatureCall(
    _ request: Server_CreatureId,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Server_CreatureId, Server_Creature>

  func makeGetAllCreaturesCall(
    _ request: Server_CreatureFilter,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Server_CreatureFilter, Server_GetAllCreaturesResponse>

  func makeCreateCreatureCall(
    _ request: Server_Creature,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Server_Creature, Server_DatabaseInfo>

  func makeUpdateCreatureCall(
    _ request: Server_Creature,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Server_Creature, Server_DatabaseInfo>

  func makeStreamLogsCall(
    _ request: Server_LogFilter,
    callOptions: CallOptions?
  ) -> GRPCAsyncServerStreamingCall<Server_LogFilter, Server_LogItem>

  func makeSearchCreaturesCall(
    _ request: Server_CreatureName,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Server_CreatureName, Server_Creature>

  func makeListCreaturesCall(
    _ request: Server_CreatureFilter,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Server_CreatureFilter, Server_ListCreaturesResponse>

  func makeStreamFramesCall(
    callOptions: CallOptions?
  ) -> GRPCAsyncClientStreamingCall<Server_Frame, Server_FrameResponse>

  func makeGetServerStatusCall(
    _ request: SwiftProtobuf.Google_Protobuf_Empty,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<SwiftProtobuf.Google_Protobuf_Empty, Server_ServerStatus>

  func makeCreateAnimationCall(
    _ request: Server_Animation,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Server_Animation, Server_DatabaseInfo>

  func makeListAnimationsCall(
    _ request: Server_AnimationFilter,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Server_AnimationFilter, Server_ListAnimationsResponse>

  func makeGetAnimationCall(
    _ request: Server_AnimationId,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Server_AnimationId, Server_Animation>
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Server_CreatureServerAsyncClientProtocol {
  public static var serviceDescriptor: GRPCServiceDescriptor {
    return Server_CreatureServerClientMetadata.serviceDescriptor
  }

  public var interceptors: Server_CreatureServerClientInterceptorFactoryProtocol? {
    return nil
  }

  public func makeGetCreatureCall(
    _ request: Server_CreatureId,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Server_CreatureId, Server_Creature> {
    return self.makeAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.getCreature.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetCreatureInterceptors() ?? []
    )
  }

  public func makeGetAllCreaturesCall(
    _ request: Server_CreatureFilter,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Server_CreatureFilter, Server_GetAllCreaturesResponse> {
    return self.makeAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.getAllCreatures.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetAllCreaturesInterceptors() ?? []
    )
  }

  public func makeCreateCreatureCall(
    _ request: Server_Creature,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Server_Creature, Server_DatabaseInfo> {
    return self.makeAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.createCreature.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeCreateCreatureInterceptors() ?? []
    )
  }

  public func makeUpdateCreatureCall(
    _ request: Server_Creature,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Server_Creature, Server_DatabaseInfo> {
    return self.makeAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.updateCreature.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeUpdateCreatureInterceptors() ?? []
    )
  }

  public func makeStreamLogsCall(
    _ request: Server_LogFilter,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncServerStreamingCall<Server_LogFilter, Server_LogItem> {
    return self.makeAsyncServerStreamingCall(
      path: Server_CreatureServerClientMetadata.Methods.streamLogs.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeStreamLogsInterceptors() ?? []
    )
  }

  public func makeSearchCreaturesCall(
    _ request: Server_CreatureName,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Server_CreatureName, Server_Creature> {
    return self.makeAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.searchCreatures.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeSearchCreaturesInterceptors() ?? []
    )
  }

  public func makeListCreaturesCall(
    _ request: Server_CreatureFilter,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Server_CreatureFilter, Server_ListCreaturesResponse> {
    return self.makeAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.listCreatures.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeListCreaturesInterceptors() ?? []
    )
  }

  public func makeStreamFramesCall(
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncClientStreamingCall<Server_Frame, Server_FrameResponse> {
    return self.makeAsyncClientStreamingCall(
      path: Server_CreatureServerClientMetadata.Methods.streamFrames.path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeStreamFramesInterceptors() ?? []
    )
  }

  public func makeGetServerStatusCall(
    _ request: SwiftProtobuf.Google_Protobuf_Empty,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<SwiftProtobuf.Google_Protobuf_Empty, Server_ServerStatus> {
    return self.makeAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.getServerStatus.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetServerStatusInterceptors() ?? []
    )
  }

  public func makeCreateAnimationCall(
    _ request: Server_Animation,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Server_Animation, Server_DatabaseInfo> {
    return self.makeAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.createAnimation.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeCreateAnimationInterceptors() ?? []
    )
  }

  public func makeListAnimationsCall(
    _ request: Server_AnimationFilter,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Server_AnimationFilter, Server_ListAnimationsResponse> {
    return self.makeAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.listAnimations.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeListAnimationsInterceptors() ?? []
    )
  }

  public func makeGetAnimationCall(
    _ request: Server_AnimationId,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Server_AnimationId, Server_Animation> {
    return self.makeAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.getAnimation.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetAnimationInterceptors() ?? []
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Server_CreatureServerAsyncClientProtocol {
  public func getCreature(
    _ request: Server_CreatureId,
    callOptions: CallOptions? = nil
  ) async throws -> Server_Creature {
    return try await self.performAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.getCreature.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetCreatureInterceptors() ?? []
    )
  }

  public func getAllCreatures(
    _ request: Server_CreatureFilter,
    callOptions: CallOptions? = nil
  ) async throws -> Server_GetAllCreaturesResponse {
    return try await self.performAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.getAllCreatures.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetAllCreaturesInterceptors() ?? []
    )
  }

  public func createCreature(
    _ request: Server_Creature,
    callOptions: CallOptions? = nil
  ) async throws -> Server_DatabaseInfo {
    return try await self.performAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.createCreature.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeCreateCreatureInterceptors() ?? []
    )
  }

  public func updateCreature(
    _ request: Server_Creature,
    callOptions: CallOptions? = nil
  ) async throws -> Server_DatabaseInfo {
    return try await self.performAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.updateCreature.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeUpdateCreatureInterceptors() ?? []
    )
  }

  public func streamLogs(
    _ request: Server_LogFilter,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncResponseStream<Server_LogItem> {
    return self.performAsyncServerStreamingCall(
      path: Server_CreatureServerClientMetadata.Methods.streamLogs.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeStreamLogsInterceptors() ?? []
    )
  }

  public func searchCreatures(
    _ request: Server_CreatureName,
    callOptions: CallOptions? = nil
  ) async throws -> Server_Creature {
    return try await self.performAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.searchCreatures.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeSearchCreaturesInterceptors() ?? []
    )
  }

  public func listCreatures(
    _ request: Server_CreatureFilter,
    callOptions: CallOptions? = nil
  ) async throws -> Server_ListCreaturesResponse {
    return try await self.performAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.listCreatures.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeListCreaturesInterceptors() ?? []
    )
  }

  public func streamFrames<RequestStream>(
    _ requests: RequestStream,
    callOptions: CallOptions? = nil
  ) async throws -> Server_FrameResponse where RequestStream: Sequence, RequestStream.Element == Server_Frame {
    return try await self.performAsyncClientStreamingCall(
      path: Server_CreatureServerClientMetadata.Methods.streamFrames.path,
      requests: requests,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeStreamFramesInterceptors() ?? []
    )
  }

  public func streamFrames<RequestStream>(
    _ requests: RequestStream,
    callOptions: CallOptions? = nil
  ) async throws -> Server_FrameResponse where RequestStream: AsyncSequence & Sendable, RequestStream.Element == Server_Frame {
    return try await self.performAsyncClientStreamingCall(
      path: Server_CreatureServerClientMetadata.Methods.streamFrames.path,
      requests: requests,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeStreamFramesInterceptors() ?? []
    )
  }

  public func getServerStatus(
    _ request: SwiftProtobuf.Google_Protobuf_Empty,
    callOptions: CallOptions? = nil
  ) async throws -> Server_ServerStatus {
    return try await self.performAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.getServerStatus.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetServerStatusInterceptors() ?? []
    )
  }

  public func createAnimation(
    _ request: Server_Animation,
    callOptions: CallOptions? = nil
  ) async throws -> Server_DatabaseInfo {
    return try await self.performAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.createAnimation.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeCreateAnimationInterceptors() ?? []
    )
  }

  public func listAnimations(
    _ request: Server_AnimationFilter,
    callOptions: CallOptions? = nil
  ) async throws -> Server_ListAnimationsResponse {
    return try await self.performAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.listAnimations.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeListAnimationsInterceptors() ?? []
    )
  }

  public func getAnimation(
    _ request: Server_AnimationId,
    callOptions: CallOptions? = nil
  ) async throws -> Server_Animation {
    return try await self.performAsyncUnaryCall(
      path: Server_CreatureServerClientMetadata.Methods.getAnimation.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetAnimationInterceptors() ?? []
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct Server_CreatureServerAsyncClient: Server_CreatureServerAsyncClientProtocol {
  public var channel: GRPCChannel
  public var defaultCallOptions: CallOptions
  public var interceptors: Server_CreatureServerClientInterceptorFactoryProtocol?

  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Server_CreatureServerClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

#endif // compiler(>=5.6)

public protocol Server_CreatureServerClientInterceptorFactoryProtocol: GRPCSendable {

  /// - Returns: Interceptors to use when invoking 'getCreature'.
  func makeGetCreatureInterceptors() -> [ClientInterceptor<Server_CreatureId, Server_Creature>]

  /// - Returns: Interceptors to use when invoking 'getAllCreatures'.
  func makeGetAllCreaturesInterceptors() -> [ClientInterceptor<Server_CreatureFilter, Server_GetAllCreaturesResponse>]

  /// - Returns: Interceptors to use when invoking 'createCreature'.
  func makeCreateCreatureInterceptors() -> [ClientInterceptor<Server_Creature, Server_DatabaseInfo>]

  /// - Returns: Interceptors to use when invoking 'updateCreature'.
  func makeUpdateCreatureInterceptors() -> [ClientInterceptor<Server_Creature, Server_DatabaseInfo>]

  /// - Returns: Interceptors to use when invoking 'streamLogs'.
  func makeStreamLogsInterceptors() -> [ClientInterceptor<Server_LogFilter, Server_LogItem>]

  /// - Returns: Interceptors to use when invoking 'searchCreatures'.
  func makeSearchCreaturesInterceptors() -> [ClientInterceptor<Server_CreatureName, Server_Creature>]

  /// - Returns: Interceptors to use when invoking 'listCreatures'.
  func makeListCreaturesInterceptors() -> [ClientInterceptor<Server_CreatureFilter, Server_ListCreaturesResponse>]

  /// - Returns: Interceptors to use when invoking 'streamFrames'.
  func makeStreamFramesInterceptors() -> [ClientInterceptor<Server_Frame, Server_FrameResponse>]

  /// - Returns: Interceptors to use when invoking 'getServerStatus'.
  func makeGetServerStatusInterceptors() -> [ClientInterceptor<SwiftProtobuf.Google_Protobuf_Empty, Server_ServerStatus>]

  /// - Returns: Interceptors to use when invoking 'createAnimation'.
  func makeCreateAnimationInterceptors() -> [ClientInterceptor<Server_Animation, Server_DatabaseInfo>]

  /// - Returns: Interceptors to use when invoking 'listAnimations'.
  func makeListAnimationsInterceptors() -> [ClientInterceptor<Server_AnimationFilter, Server_ListAnimationsResponse>]

  /// - Returns: Interceptors to use when invoking 'getAnimation'.
  func makeGetAnimationInterceptors() -> [ClientInterceptor<Server_AnimationId, Server_Animation>]
}

public enum Server_CreatureServerClientMetadata {
  public static let serviceDescriptor = GRPCServiceDescriptor(
    name: "CreatureServer",
    fullName: "server.CreatureServer",
    methods: [
      Server_CreatureServerClientMetadata.Methods.getCreature,
      Server_CreatureServerClientMetadata.Methods.getAllCreatures,
      Server_CreatureServerClientMetadata.Methods.createCreature,
      Server_CreatureServerClientMetadata.Methods.updateCreature,
      Server_CreatureServerClientMetadata.Methods.streamLogs,
      Server_CreatureServerClientMetadata.Methods.searchCreatures,
      Server_CreatureServerClientMetadata.Methods.listCreatures,
      Server_CreatureServerClientMetadata.Methods.streamFrames,
      Server_CreatureServerClientMetadata.Methods.getServerStatus,
      Server_CreatureServerClientMetadata.Methods.createAnimation,
      Server_CreatureServerClientMetadata.Methods.listAnimations,
      Server_CreatureServerClientMetadata.Methods.getAnimation,
    ]
  )

  public enum Methods {
    public static let getCreature = GRPCMethodDescriptor(
      name: "GetCreature",
      path: "/server.CreatureServer/GetCreature",
      type: GRPCCallType.unary
    )

    public static let getAllCreatures = GRPCMethodDescriptor(
      name: "GetAllCreatures",
      path: "/server.CreatureServer/GetAllCreatures",
      type: GRPCCallType.unary
    )

    public static let createCreature = GRPCMethodDescriptor(
      name: "CreateCreature",
      path: "/server.CreatureServer/CreateCreature",
      type: GRPCCallType.unary
    )

    public static let updateCreature = GRPCMethodDescriptor(
      name: "UpdateCreature",
      path: "/server.CreatureServer/UpdateCreature",
      type: GRPCCallType.unary
    )

    public static let streamLogs = GRPCMethodDescriptor(
      name: "StreamLogs",
      path: "/server.CreatureServer/StreamLogs",
      type: GRPCCallType.serverStreaming
    )

    public static let searchCreatures = GRPCMethodDescriptor(
      name: "SearchCreatures",
      path: "/server.CreatureServer/SearchCreatures",
      type: GRPCCallType.unary
    )

    public static let listCreatures = GRPCMethodDescriptor(
      name: "ListCreatures",
      path: "/server.CreatureServer/ListCreatures",
      type: GRPCCallType.unary
    )

    public static let streamFrames = GRPCMethodDescriptor(
      name: "StreamFrames",
      path: "/server.CreatureServer/StreamFrames",
      type: GRPCCallType.clientStreaming
    )

    public static let getServerStatus = GRPCMethodDescriptor(
      name: "GetServerStatus",
      path: "/server.CreatureServer/GetServerStatus",
      type: GRPCCallType.unary
    )

    public static let createAnimation = GRPCMethodDescriptor(
      name: "CreateAnimation",
      path: "/server.CreatureServer/CreateAnimation",
      type: GRPCCallType.unary
    )

    public static let listAnimations = GRPCMethodDescriptor(
      name: "ListAnimations",
      path: "/server.CreatureServer/ListAnimations",
      type: GRPCCallType.unary
    )

    public static let getAnimation = GRPCMethodDescriptor(
      name: "GetAnimation",
      path: "/server.CreatureServer/GetAnimation",
      type: GRPCCallType.unary
    )
  }
}

