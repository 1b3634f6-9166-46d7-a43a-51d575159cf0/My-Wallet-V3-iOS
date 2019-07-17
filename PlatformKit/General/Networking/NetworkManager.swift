//
//  NetworkManager.swift
//  Blockchain
//
//  Created by Maurice A. on 4/16/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import Alamofire
import RxSwift

public typealias AuthChallengeHandler = (URLSession.AuthChallengeDisposition, URLCredential?) -> Swift.Void

typealias JSON = [String: Any]

public typealias URLParameters = [String: Any]

/**
 Manages network related tasks such as requests and sessions.
 # Usage
 TBD
 - Author: Maurice Achtenhagen
 - Copyright: Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
 */


@objc
open class NetworkManager: NSObject, URLSessionDelegate {

    // MARK: - Properties

    /// The instance variable used to access functions of the `NetworkManager` class.
    public static let shared = NetworkManager()

    /// Default unknown network error
    static let unknownNetworkError = NSError(domain: "NetworkManagerDomain", code: -1, userInfo: nil)

    // TODO: remove once migration is complete
    /// Objective-C compatible class function
    @objc public class func sharedInstance() -> NetworkManager {
        return NetworkManager.shared
    }

    @objc public var session: URLSession!

    fileprivate var sessionConfiguration: URLSessionConfiguration!

    // MARK: - Initialization

    public override init() {
        super.init()
        sessionConfiguration = URLSessionConfiguration.default
        if let userAgent = NetworkManager.userAgent {
            sessionConfiguration.httpAdditionalHeaders = [HttpHeaderField.userAgent: userAgent]
        }
        if #available(iOS 11.0, *) {
            sessionConfiguration.waitsForConnectivity = true
        }
        session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        disableUIWebViewCaching()
        persistServerSessionIDForNewUIWebViews()
    }

    // MARK: - Post
    
    /// Post that accepts an encodable as parameter
    public func post<T: Decodable>(_ relativeUrl: String,
                                   data: Encodable,
                                   decodeTo decodableType: T.Type,
                                   onErrorJustReturn: Bool = false) -> Single<T> {
        return post(relativeUrl,
                    parameters: data.dictionary,
                    decodeTo: decodableType,
                    onErrorJustReturn: onErrorJustReturn)
    }
    
    /// Post that accepts a dictionary as parameter
    public func post<T: Decodable>(_ relativeUrl: String,
                                   parameters: [String: Any] = [:],
                                   decodeTo decodableType: T.Type,
                                   onErrorJustReturn: Bool = false) -> Single<T> {
        return request(.post,
                       relativeUrl: relativeUrl,
                       parameters: parameters,
                       decodeTo: decodableType,
                       onErrorJustReturn: onErrorJustReturn)
    }
    
    // MARK: - Get
    
    public func get<T: Decodable>(_ relativeUrl: String,
                                  decodeTo decodableType: T.Type,
                                  onErrorJustReturn: Bool = false) -> Single<T> {
        return request(.get,
                       relativeUrl: relativeUrl,
                       decodeTo: decodableType,
                       onErrorJustReturn: onErrorJustReturn)
    }
    
    // MARK: - Put
    
    public func put<T: Decodable>(_ relativeUrl: String,
                                  data: Encodable,
                                  decodeTo decodableType: T.Type,
                                  onErrorJustReturn: Bool = false) -> Single<T> {
        return put(relativeUrl,
                   parameters: data.dictionary,
                   decodeTo: decodableType,
                   onErrorJustReturn: onErrorJustReturn)
    }
    
    public func put<T: Decodable>(_ relativeUrl: String,
                                  parameters: [String: Any] = [:],
                                  decodeTo decodableType: T.Type,
                                  onErrorJustReturn: Bool = false) -> Single<T> {
        return request(.put,
                       relativeUrl: relativeUrl,
                       parameters: parameters,
                       decodeTo: decodableType,
                       onErrorJustReturn: onErrorJustReturn)
    }
    
    // MARK: - Delete
    
    public func delete<T: Decodable>(_ relativeUrl: String,
                                     decodeTo decodableType: T.Type,
                                     onErrorJustReturn: Bool = false) -> Single<T> {
        return request(.delete,
                       relativeUrl: relativeUrl,
                       decodeTo: decodableType,
                       onErrorJustReturn: onErrorJustReturn)
    }
    
    // MARK: - Generic Request
    
    private func request<T: Decodable>(_ method: HTTPMethod,
                                       relativeUrl: String,
                                       parameters: [String: Any]? = nil,
                                       decodeTo decodableType: T.Type,
                                       onErrorJustReturn: Bool = false) -> Single<T> {
        return Single<DataRequest>.create { single -> Disposable in
            let request = SessionManager.default.request(
                relativeUrl,
                method: method,
                parameters: parameters,
                encoding: URLEncoding.default,
                headers: nil)
            single(.success(request))
            return Disposables.create()
        }
        .flatMap { request -> Single<(HTTPURLResponse, Data)> in
            return request.responseData()
        }
        .map { (response, data) -> T in
            guard onErrorJustReturn || (200...299).contains(response.statusCode) else {
                throw NetworkError.badStatusCode
            }
            return try data.decode(to: decodableType)
        }
    }
    
    public func request<ResponseType: Decodable>(
        _ request: URLRequest,
        responseType: ResponseType.Type
    ) -> Single<ResponseType> {
        return requestData(request).map { (response, result) in
            guard (200...299).contains(response.statusCode) else {
                throw NetworkError.badStatusCode
            }
            return try JSONDecoder().decode(responseType.self, from: result)
        }
    }

    public func requestData(_ request: URLRequest) -> Single<(HTTPURLResponse, Data)> {
        let dataRequestSingle: Single<DataRequest> = Single.create { observer -> Disposable in
            let dataRequest = SessionManager.default.request(request)
            Logger.shared.debug("Sending \(request.httpMethod ?? "") to '\(request.url?.absoluteString ?? "")'")
            observer(.success(dataRequest))
            return Disposables.create()
        }
        return dataRequestSingle.flatMap { $0.responseData() }
    }

    /// Performs a network request and returns a Single emitting the HTTPURLResponse along with the
    /// response decoded as a Data object.
    ///
    /// - Parameters:
    ///   - url: the URL
    ///   - method: the HTTP method
    ///   - parameters: optional parameters for the request
    ///   - headers: optional headers
    /// - Returns: the Single
    public func requestData(
        _ url: String,
        method: HttpMethod,
        parameters: URLParameters? = nil,
        headers: [String: String]? = nil
    ) -> Single<(HTTPURLResponse, Data)> {
        let dataRequestSingle: Single<DataRequest> = Single.create { observer -> Disposable in
            let request = SessionManager.default.request(
                url,
                method: method.toAlamofireHTTPMethod,
                parameters: parameters,
                encoding: URLEncoding.default,
                headers: headers
            )
            observer(.success(request))
            return Disposables.create()
        }
        return dataRequestSingle.flatMap { $0.responseData() }
    }

    /// Performs a network request and returns an Observable emitting the HTTPURLResponse along with the
    /// decoded response data. The response data will be attempted to be decoded as a JSON, however if it
    /// fails, it will be attempted to be decoded as a String. It is up to the observer to check the type.
    ///
    /// - Parameters:
    ///   - url: the URL for the request (e.g. "http://blockchain.info/uuid-generator?n=3")
    ///   - method: the HTTP method
    ///   - parameters: the parameters for the request
    /// - Returns: a Single returning the HTTPURLResponse and the decoded response data
    open func requestJsonOrString(
        _ url: String,
        method: HttpMethod,
        parameters: URLParameters? = nil,
        headers: [String: String]? = nil
    ) -> Single<(HTTPURLResponse, Any)> {
        let dataRequestSingle: Single<DataRequest> = Single.create { observer -> Disposable in
            let request = SessionManager.default.request(
                url,
                method: method.toAlamofireHTTPMethod,
                parameters: parameters,
                encoding: URLEncoding.default,
                headers: headers
            )
            observer(.success(request))
            return Disposables.create()
        }
        return dataRequestSingle.flatMap { request -> Single<(HTTPURLResponse, Any)> in
            return request.responseJSONSingle()
                .catchError { _ -> Single<(HTTPURLResponse, Any)> in
                    return request.responseStringSingle()
            }
        }
    }

    // MARK: - URLSessionDelegate

    // TODO: find place to put UIApplication.shared.isNetworkActivityIndicatorVisible

    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {}

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping AuthChallengeHandler) {
        let host = challenge.protectionSpace.host
        Logger.shared.info("Received challenge from \(host)")

        #if DISABLE_CERT_PINNING
        completionHandler(.performDefaultHandling, nil)
        #else
        if  BlockchainAPI.PartnerHosts.allCases.contains(where: { $0.rawValue == host }) {
            completionHandler(.performDefaultHandling, nil)
        } else {
            CertificatePinner.shared.didReceive(challenge, completion: completionHandler)
        }
        #endif
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {}

    // MARK: - Private Functions

    fileprivate func persistServerSessionIDForNewUIWebViews() {
        let cookieStorage = HTTPCookieStorage.shared
        cookieStorage.cookieAcceptPolicy = .always
    }

    fileprivate func disableUIWebViewCaching() {
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
    }
}

extension DataRequest {
    public func responseData() -> Single<(HTTPURLResponse, Data)> {
        return Single.create { [unowned self] observer -> Disposable in
            self.responseData { dataResponse in
                if let error = dataResponse.result.error {
                    observer(.error(error))
                    return
                }
                guard let response = dataResponse.response, let result = dataResponse.result.value else {
                    observer(.error(NetworkManager.unknownNetworkError))
                    return
                }
                observer(.success((response, result)))
            }
            return Disposables.create()
        }
    }

    public func responseJSONSingle() -> Single<(HTTPURLResponse, Any)> {
        return Single.create { [unowned self] observer -> Disposable in
            self.responseJSON { jsonResponse in
                if let error = jsonResponse.result.error {
                    observer(.error(error))
                    return
                }
                guard let response = jsonResponse.response, let result = jsonResponse.result.value else {
                    observer(.error(NetworkManager.unknownNetworkError))
                    return
                }
                observer(.success((response, result)))
            }
            return Disposables.create {
                self.cancel()
            }
        }
    }

    public func responseStringSingle() -> Single<(HTTPURLResponse, Any)> {
        return Single.create { [unowned self] observer -> Disposable in
            self.responseString { stringResponse in
                if let error = stringResponse.result.error {
                    observer(.error(error))
                    return
                }
                guard let response = stringResponse.response, let result = stringResponse.result.value else {
                    observer(.error(NetworkManager.unknownNetworkError))
                    return
                }
                observer(.success((response, result)))
            }
            return Disposables.create {
                self.cancel()
            }
        }
    }
}

extension HttpMethod {

    /// Transforms this HttpMethod to an Alamofire.HTTPMethod
    var toAlamofireHTTPMethod: HTTPMethod {
        switch self {
        case .get:
            return HTTPMethod.get
        case .post:
            return HTTPMethod.post
        case .put:
            return HTTPMethod.put
        case .patch:
            return HTTPMethod.patch
        }
    }
}

extension Data {
    func decode<T: Decodable>(to type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        do {
            try decoder.decode(type, from: self)
        } catch {
            print(error)
        }
        let decodable = try decoder.decode(type, from: self)
        return decodable
    }
}

extension Encodable {
    var dictionary: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else {
            return [:]
        }
        return (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)) as? [String: Any] ?? [:]
    }
}

