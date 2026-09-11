import BeakyCommunicatorCore
import Foundation
import HTTPTypes
import Hummingbird
import Logging
import ServiceLifecycle
import WorldCore

public struct CommunicatorGatewayErrorResponse: Equatable, Sendable, Codable {
    public var error: String
    public var message: String

    public init(error: String, message: String) {
        self.error = error
        self.message = message
    }
}

enum ForegroundLeaseHTTPAPIError: Error {
    case unsupportedMediaType
    case leaseNotFound
}

public struct ForegroundLeaseHTTPAPI: Sendable {
    public static let maximumBodyBytes = 4_096

    private let registry: ForegroundLeaseRegistry

    public init(registry: ForegroundLeaseRegistry) {
        self.registry = registry
    }

    public func addRoutes(to router: RouterGroup<BasicRequestContext>) {
        router.post("v1/foreground-leases") { request, _ in
            await respond {
                try requireJSON(request)
                let command = try await decode(ForegroundLeaseCommand.self, from: request)
                let lease = try await registry.acquire(
                    installationID: command.installationID,
                    sessionID: command.sessionID
                )
                return try jsonResponse(lease, status: .created)
            }
        }

        router.put("v1/foreground-leases") { request, _ in
            await respond {
                try requireJSON(request)
                let command = try await decode(ForegroundLeaseCommand.self, from: request)
                guard
                    let lease = await registry.renew(
                        installationID: command.installationID,
                        sessionID: command.sessionID
                    )
                else {
                    throw ForegroundLeaseHTTPAPIError.leaseNotFound
                }
                return try jsonResponse(lease)
            }
        }

        router.delete("v1/foreground-leases") { request, _ in
            await respond {
                try requireJSON(request)
                let command = try await decode(ForegroundLeaseCommand.self, from: request)
                _ = await registry.release(
                    installationID: command.installationID,
                    sessionID: command.sessionID
                )
                return Response(status: .noContent)
            }
        }
    }

    private func requireJSON(_ request: Request) throws {
        guard let contentType = request.headers[.contentType]?.lowercased(),
            contentType == "application/json" || contentType.hasPrefix("application/json;")
        else {
            throw ForegroundLeaseHTTPAPIError.unsupportedMediaType
        }
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from request: Request
    ) async throws -> Value {
        let body = try await request.body.collect(upTo: Self.maximumBodyBytes)
        return try WorldJSON.makeDecoder().decode(type, from: body)
    }

    private func respond(_ operation: () async throws -> Response) async -> Response {
        do {
            return try await operation()
        } catch {
            return (try? errorResponse(for: error)) ?? Response(status: .internalServerError)
        }
    }

    private func errorResponse(for error: any Error) throws -> Response {
        switch error {
        case ForegroundLeaseHTTPAPIError.unsupportedMediaType:
            return try jsonResponse(
                CommunicatorGatewayErrorResponse(
                    error: "unsupported_media_type",
                    message: "Content-Type must be application/json"
                ),
                status: .unsupportedMediaType
            )
        case ForegroundLeaseHTTPAPIError.leaseNotFound:
            return try jsonResponse(
                CommunicatorGatewayErrorResponse(
                    error: "lease_not_found",
                    message: "The foreground lease no longer exists"
                ),
                status: .notFound
            )
        case let registryError as ForegroundLeaseRegistryError:
            return try jsonResponse(
                CommunicatorGatewayErrorResponse(
                    error: "lease_capacity_exceeded",
                    message: registryError.localizedDescription
                ),
                status: .serviceUnavailable
            )
        case is DecodingError:
            return try jsonResponse(
                CommunicatorGatewayErrorResponse(
                    error: "invalid_request",
                    message: "The foreground lease request is invalid"
                ),
                status: .badRequest
            )
        case let responseError as any HTTPResponseError
        where responseError.status == .contentTooLarge:
            return try jsonResponse(
                CommunicatorGatewayErrorResponse(
                    error: "body_too_large",
                    message: "The request body exceeds the allowed size"
                ),
                status: .contentTooLarge
            )
        default:
            return try jsonResponse(
                CommunicatorGatewayErrorResponse(
                    error: "internal_error",
                    message: "The communicator gateway could not complete the request"
                ),
                status: .internalServerError
            )
        }
    }

    private func jsonResponse<Value: Encodable>(
        _ value: Value,
        status: HTTPResponse.Status = .ok
    ) throws -> Response {
        let data = try WorldJSON.makeEncoder().encode(value)
        return Response(
            status: status,
            headers: [.contentType: "application/json; charset=utf-8"],
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
        )
    }
}

public func makeCommunicatorGatewayApplication(
    registry: ForegroundLeaseRegistry,
    configuration: CommunicatorGatewayConfiguration = .default,
    services: [any Service] = [],
    logger: Logger = Logger(label: "creature-communicator-gateway")
) -> Application<RouterResponder<BasicRequestContext>> {
    let router = Router(context: BasicRequestContext.self)
    router.middlewares.add(TracingMiddleware())
    router.addMiddleware { LogRequestsMiddleware(.debug) }
    let routes = router.group("communicator")
    routes.get("v1/health") { _, _ in
        CommunicatorGatewayHealthResponse(
            status: "ok",
            service: "creature-communicator-gateway",
            buildVersion: CommunicatorGatewayBuildInfo.current.version
        )
    }
    ForegroundLeaseHTTPAPI(registry: registry).addRoutes(to: routes)
    return Application(
        router: router,
        configuration: .init(
            address: .hostname(configuration.host, port: configuration.port),
            serverName: "creature-communicator-gateway"
        ),
        services: services + [CommunicatorGatewayLifecycleReporter(logger: logger)],
        onServerRunning: { _ in
            logger.info(
                "Creature Communicator Gateway is listening",
                metadata: [
                    "build.version": "\(CommunicatorGatewayBuildInfo.current.version)",
                    "http.host": "\(configuration.host)",
                    "http.port": "\(configuration.port)",
                ]
            )
        },
        logger: logger
    )
}

extension CommunicatorGatewayHealthResponse: ResponseEncodable {}
