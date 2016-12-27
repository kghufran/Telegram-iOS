import Foundation
#if os(macOS)
    import PostboxMac
    import SwiftSignalKitMac
    import MtProtoKitMac
#else
    import Postbox
    import SwiftSignalKit
    import MtProtoKitDynamic
#endif
import TelegramCorePrivateModule

public struct AccountId: Comparable, Hashable {
    let stringValue: String
    
    public static func ==(lhs: AccountId, rhs: AccountId) -> Bool {
        return lhs.stringValue == rhs.stringValue
    }
    
    public static func <(lhs: AccountId, rhs: AccountId) -> Bool {
        return lhs.stringValue < rhs.stringValue
    }
    
    public var hashValue: Int {
        return self.stringValue.hash
    }
}

public class AccountState: Coding, Equatable {
    public required init(decoder: Decoder) {
    }
    
    public func encode(_ encoder: Encoder) {
    }
    
    fileprivate init() {
    }
    
    fileprivate func equalsTo(_ other: AccountState) -> Bool {
        return false
    }
}

public func ==(lhs: AccountState, rhs: AccountState) -> Bool {
    return lhs.equalsTo(rhs)
}

public final class UnauthorizedAccountState: AccountState {
    let masterDatacenterId: Int32
    
    public required init(decoder: Decoder) {
        self.masterDatacenterId = decoder.decodeInt32ForKey("masterDatacenterId")
        super.init()
    }
    
    override public func encode(_ encoder: Encoder) {
        encoder.encodeInt32(self.masterDatacenterId, forKey: "masterDatacenterId")
    }
    
    init(masterDatacenterId: Int32) {
        self.masterDatacenterId = masterDatacenterId
        super.init()
    }
    
    override func equalsTo(_ other: AccountState) -> Bool {
        if let other = other as? UnauthorizedAccountState {
            return self.masterDatacenterId == other.masterDatacenterId
        } else {
            return false
        }
    }
}

public class AuthorizedAccountState: AccountState {
    public final class State: Coding, Equatable, CustomStringConvertible {
        let pts: Int32
        let qts: Int32
        let date: Int32
        let seq: Int32
        
        init(pts: Int32, qts: Int32, date: Int32, seq: Int32) {
            self.pts = pts
            self.qts = qts
            self.date = date
            self.seq = seq
        }
        
        public init(decoder: Decoder) {
            self.pts = decoder.decodeInt32ForKey("pts")
            self.qts = decoder.decodeInt32ForKey("qts")
            self.date = decoder.decodeInt32ForKey("date")
            self.seq = decoder.decodeInt32ForKey("seq")
        }
        
        public func encode(_ encoder: Encoder) {
            encoder.encodeInt32(self.pts, forKey: "pts")
            encoder.encodeInt32(self.qts, forKey: "qts")
            encoder.encodeInt32(self.date, forKey: "date")
            encoder.encodeInt32(self.seq, forKey: "seq")
        }
        
        public var description: String {
            return "(pts: \(pts), qts: \(qts), seq: \(seq), date: \(date))"
        }
    }
    
    let masterDatacenterId: Int32
    let peerId: PeerId
    
    let state: State?
    
    public required init(decoder: Decoder) {
        self.masterDatacenterId = decoder.decodeInt32ForKey("masterDatacenterId")
        self.peerId = PeerId(decoder.decodeInt64ForKey("peerId"))
        self.state = decoder.decodeObjectForKey("state", decoder: { return State(decoder: $0) }) as? State
        
        super.init()
    }
    
    override public func encode(_ encoder: Encoder) {
        encoder.encodeInt32(self.masterDatacenterId, forKey: "masterDatacenterId")
        encoder.encodeInt64(self.peerId.toInt64(), forKey: "peerId")
        if let state = self.state {
            encoder.encodeObject(state, forKey: "state")
        }
    }
    
    public init(masterDatacenterId: Int32, peerId: PeerId, state: State?) {
        self.masterDatacenterId = masterDatacenterId
        self.peerId = peerId
        self.state = state
        
        super.init()
    }
    
    func changedState(_ state: State) -> AuthorizedAccountState {
        return AuthorizedAccountState(masterDatacenterId: self.masterDatacenterId, peerId: self.peerId, state: state)
    }
    
    override func equalsTo(_ other: AccountState) -> Bool {
        if let other = other as? AuthorizedAccountState {
            return self.masterDatacenterId == other.masterDatacenterId &&
                self.peerId == other.peerId &&
                self.state == other.state
        } else {
            return false
        }
    }
}

public func ==(lhs: AuthorizedAccountState.State, rhs: AuthorizedAccountState.State) -> Bool {
    return lhs.pts == rhs.pts &&
        lhs.qts == rhs.qts &&
        lhs.date == rhs.date &&
        lhs.seq == rhs.seq
}

public func currentAccountId(appGroupPath: String) -> AccountId {
    let filePath = "\(appGroupPath)/currentAccountId"
    if let id = try? String(contentsOfFile: filePath) {
        return AccountId(stringValue: id)
    } else {
        let id = generateAccountId()
        let _ = try? id.stringValue.write(toFile: filePath, atomically: true, encoding: .utf8)
        return id
    }
}

public func generateAccountId() -> AccountId {
    return AccountId(stringValue: NSUUID().uuidString)
}

public class UnauthorizedAccount {
    public let id: AccountId
    public let basePath: String
    public let postbox: Postbox
    public let network: Network
    
    public var masterDatacenterId: Int32 {
        return Int32(self.network.mtProto.datacenterId)
    }
    
    init(id: AccountId, basePath: String, postbox: Postbox, network: Network) {
        self.id = id
        self.basePath = basePath
        self.postbox = postbox
        self.network = network
    }
    
    public func changedMasterDatacenterId(_ masterDatacenterId: Int32) -> Signal<UnauthorizedAccount, NoError> {
        if masterDatacenterId == Int32(self.network.mtProto.datacenterId) {
            return .single(self)
        } else {
            let postbox = self.postbox
            let keychain = Keychain(get: { key in
                return postbox.keychainEntryForKey(key)
            }, set: { (key, data) in
                postbox.setKeychainEntryForKey(key, value: data)
            }, remove: { key in
                postbox.removeKeychainEntryForKey(key)
            })
            
            return initializedNetwork(datacenterId: Int(masterDatacenterId), keychain: keychain, networkUsageInfoPath: accountNetworkUsageInfoPath(basePath: self.basePath))
                |> map { network in
                    return UnauthorizedAccount(id: self.id, basePath: self.basePath, postbox: self.postbox, network: network)
                }
        }
    }
}

private var declaredEncodables: Void = {
    declareEncodable(UnauthorizedAccountState.self, f: { UnauthorizedAccountState(decoder: $0) })
    declareEncodable(AuthorizedAccountState.self, f: { AuthorizedAccountState(decoder: $0) })
    declareEncodable(TelegramUser.self, f: { TelegramUser(decoder: $0) })
    declareEncodable(TelegramGroup.self, f: { TelegramGroup(decoder: $0) })
    declareEncodable(TelegramChannel.self, f: { TelegramChannel(decoder: $0) })
    declareEncodable(TelegramMediaImage.self, f: { TelegramMediaImage(decoder: $0) })
    declareEncodable(TelegramMediaImageRepresentation.self, f: { TelegramMediaImageRepresentation(decoder: $0) })
    declareEncodable(TelegramMediaContact.self, f: { TelegramMediaContact(decoder: $0) })
    declareEncodable(TelegramMediaMap.self, f: { TelegramMediaMap(decoder: $0) })
    declareEncodable(TelegramMediaFile.self, f: { TelegramMediaFile(decoder: $0) })
    declareEncodable(TelegramMediaFileAttribute.self, f: { TelegramMediaFileAttribute(decoder: $0) })
    declareEncodable(CloudFileMediaResource.self, f: { CloudFileMediaResource(decoder: $0) })
    declareEncodable(ChannelState.self, f: { ChannelState(decoder: $0) })
    declareEncodable(InlineBotMessageAttribute.self, f: { InlineBotMessageAttribute(decoder: $0) })
    declareEncodable(TextEntitiesMessageAttribute.self, f: { TextEntitiesMessageAttribute(decoder: $0) })
    declareEncodable(ReplyMessageAttribute.self, f: { ReplyMessageAttribute(decoder: $0) })
    declareEncodable(CloudDocumentMediaResource.self, f: { CloudDocumentMediaResource(decoder: $0) })
    declareEncodable(TelegramMediaWebpage.self, f: { TelegramMediaWebpage(decoder: $0) })
    declareEncodable(ViewCountMessageAttribute.self, f: { ViewCountMessageAttribute(decoder: $0) })
    declareEncodable(TelegramMediaAction.self, f: { TelegramMediaAction(decoder: $0) })
    declareEncodable(TelegramPeerNotificationSettings.self, f: { TelegramPeerNotificationSettings(decoder: $0) })
    declareEncodable(CachedUserData.self, f: { CachedUserData(decoder: $0) })
    declareEncodable(BotInfo.self, f: { BotInfo(decoder: $0) })
    declareEncodable(CachedGroupData.self, f: { CachedGroupData(decoder: $0) })
    declareEncodable(CachedChannelData.self, f: { CachedChannelData(decoder: $0) })
    declareEncodable(TelegramUserPresence.self, f: { TelegramUserPresence(decoder: $0) })
    declareEncodable(LocalFileMediaResource.self, f: { LocalFileMediaResource(decoder: $0) })
    declareEncodable(PhotoLibraryMediaResource.self, f: { PhotoLibraryMediaResource(decoder: $0) })
    declareEncodable(StickerPackCollectionInfo.self, f: { StickerPackCollectionInfo(decoder: $0) })
    declareEncodable(StickerPackItem.self, f: { StickerPackItem(decoder: $0) })
    declareEncodable(LocalFileReferenceMediaResource.self, f: { LocalFileReferenceMediaResource(decoder: $0) })
    declareEncodable(OutgoingMessageInfoAttribute.self, f: { OutgoingMessageInfoAttribute(decoder: $0) })
    declareEncodable(ForwardSourceInfoAttribute.self, f: { ForwardSourceInfoAttribute(decoder: $0) })
    declareEncodable(EditedMessageAttribute.self, f: { EditedMessageAttribute(decoder: $0) })
    declareEncodable(ReplyMarkupMessageAttribute.self, f: { ReplyMarkupMessageAttribute(decoder: $0) })
    declareEncodable(CachedResolvedByNamePeer.self, f: { CachedResolvedByNamePeer(decoder: $0) })
    declareEncodable(OutgoingChatContextResultMessageAttribute.self, f: { OutgoingChatContextResultMessageAttribute(decoder: $0) })
    declareEncodable(HttpReferenceMediaResource.self, f: { HttpReferenceMediaResource(decoder: $0) })
    declareEncodable(EmptyMediaResource.self, f: { EmptyMediaResource(decoder: $0) })
    return
}()

func accountNetworkUsageInfoPath(basePath: String) -> String {
    return basePath + "/network-usage"
}

public func accountWithId(_ id: AccountId, appGroupPath: String) -> Signal<Either<UnauthorizedAccount, Account>, NoError> {
    return Signal<(String, Postbox, AccountState?), NoError> { subscriber in
        let _ = declaredEncodables
        
        let path = "\(appGroupPath)/account\(id.stringValue)"
        
        let seedConfiguration = SeedConfiguration(initializeChatListWithHoles: [ChatListHole(index: MessageIndex(id: MessageId(peerId: PeerId(namespace: Namespaces.Peer.Empty, id: 0), namespace: Namespaces.Message.Cloud, id: 1), timestamp: 1))], initializeMessageNamespacesWithHoles: [Namespaces.Message.Cloud], existingMessageTags: allMessageTags)
        
        let postbox = Postbox(basePath: path + "/postbox", globalMessageIdsNamespace: Namespaces.Message.Cloud, seedConfiguration: seedConfiguration)
        return (postbox.state() |> take(1) |> map { accountState in
            return (path, postbox, accountState as? AccountState)
        }).start(next: { args in
            subscriber.putNext(args)
            subscriber.putCompletion()
        })
    } |> mapToSignal { (basePath, postbox, accountState) -> Signal<Either<UnauthorizedAccount, Account>, NoError> in
        let keychain = Keychain(get: { key in
            return postbox.keychainEntryForKey(key)
        }, set: { (key, data) in
            postbox.setKeychainEntryForKey(key, value: data)
        }, remove: { key in
            postbox.removeKeychainEntryForKey(key)
        })
        
        if let accountState = accountState {
            switch accountState {
                case let unauthorizedState as UnauthorizedAccountState:
                    return initializedNetwork(datacenterId: Int(unauthorizedState.masterDatacenterId), keychain: keychain, networkUsageInfoPath: accountNetworkUsageInfoPath(basePath: basePath))
                        |> map { network -> Either<UnauthorizedAccount, Account> in
                            .left(value: UnauthorizedAccount(id: id, basePath: basePath, postbox: postbox, network: network))
                        }
                case let authorizedState as AuthorizedAccountState:
                    return initializedNetwork(datacenterId: Int(authorizedState.masterDatacenterId), keychain: keychain, networkUsageInfoPath: accountNetworkUsageInfoPath(basePath: basePath))
                        |> map { network -> Either<UnauthorizedAccount, Account> in
                            return .right(value: Account(id: id, basePath: basePath, postbox: postbox, network: network, peerId: authorizedState.peerId))
                        }
                case _:
                    assertionFailure("Unexpected accountState \(accountState)")
            }
        }
        
        return initializedNetwork(datacenterId: 2, keychain: keychain, networkUsageInfoPath: accountNetworkUsageInfoPath(basePath: basePath))
            |> map { network -> Either<UnauthorizedAccount, Account> in
                return .left(value: UnauthorizedAccount(id: id, basePath: basePath, postbox: postbox, network: network))
        }
    }
}

public struct TwoStepAuthData {
    let nextSalt: Data
    let currentSalt: Data?
    let hasRecovery: Bool
    let currentHint: String?
    let unconfirmedEmailPattern: String?
}

public func twoStepAuthData(_ network: Network) -> Signal<TwoStepAuthData, MTRpcError> {
    return network.request(Api.functions.account.getPassword())
    |> map { config -> TwoStepAuthData in
        switch config {
            case let .noPassword(newSalt, emailUnconfirmedPattern):
                return TwoStepAuthData(nextSalt: newSalt.makeData(), currentSalt: nil, hasRecovery: false, currentHint: nil, unconfirmedEmailPattern: emailUnconfirmedPattern)
            case let .password(currentSalt, newSalt, hint, hasRecovery, emailUnconfirmedPattern):
                return TwoStepAuthData(nextSalt: newSalt.makeData(), currentSalt: currentSalt.makeData(), hasRecovery: hasRecovery == .boolTrue, currentHint: hint, unconfirmedEmailPattern: emailUnconfirmedPattern)
        }
    }
}

private func sha256(_ data : Data) -> Data {
    var res = Data()
    res.count = Int(CC_SHA256_DIGEST_LENGTH)
    res.withUnsafeMutableBytes { mutableBytes -> Void in
        data.withUnsafeBytes { bytes -> Void in
            CC_SHA256(bytes, CC_LONG(data.count), mutableBytes)
        }
    }
    return res
}

public func verifyPassword(_ account: UnauthorizedAccount, password: String) -> Signal<Api.auth.Authorization, MTRpcError> {
    return twoStepAuthData(account.network)
    |> mapToSignal { authData -> Signal<Api.auth.Authorization, MTRpcError> in
        var data = Data()
        data.append(authData.currentSalt!)
        data.append(password.data(using: .utf8, allowLossyConversion: true)!)
        data.append(authData.currentSalt!)
        let currentPasswordHash = sha256(data)
        
        return account.network.request(Api.functions.auth.checkPassword(passwordHash: Buffer(data: currentPasswordHash)))
    }
}

public enum AccountServiceTaskMasterMode {
    case now
    case always
    case never
}

public class Account {
    public let id: AccountId
    public let basePath: String
    public let postbox: Postbox
    public let network: Network
    public let peerId: PeerId
    
    public private(set) var stateManager: StateManager!
    public private(set) var viewTracker: AccountViewTracker!
    public private(set) var pendingMessageManager: PendingMessageManager!
    fileprivate let managedContactsDisposable = MetaDisposable()
    fileprivate let managedStickerPacksDisposable = MetaDisposable()
    private let becomeMasterDisposable = MetaDisposable()
    private let updatedPresenceDisposable = MetaDisposable()
    private let managedServiceViewsDisposable = MetaDisposable()
    
    public let graphicsThreadPool = ThreadPool(threadCount: 3, threadPriority: 0.1)
    //let imageCache: ImageCache = ImageCache(maxResidentSize: 5 * 1024 * 1024)
    
    public var applicationContext: Any?
    
    public let settings: AccountSettings = defaultAccountSettings()
    
    var player: AnyObject?
    
    public let notificationToken = Promise<Data>()
    private let notificationTokenDisposable = MetaDisposable()
    
    public let shouldBeServiceTaskMaster = Promise<AccountServiceTaskMasterMode>()
    public let shouldKeepOnlinePresence = Promise<Bool>()
    
    
    public init(id: AccountId, basePath: String, postbox: Postbox, network: Network, peerId: PeerId) {
        self.id = id
        self.basePath = basePath
        self.postbox = postbox
        self.network = network
        self.peerId = peerId
        
        self.stateManager = StateManager(account: self)
        self.viewTracker = AccountViewTracker(account: self)
        self.pendingMessageManager = PendingMessageManager(network: network, postbox: postbox, stateManager: self.stateManager)
        
        let appliedNotificationToken = self.notificationToken.get()
            |> distinctUntilChanged
            |> mapToSignal { token -> Signal<Void, NoError> in                
                var tokenString = ""
                token.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) -> Void in
                    for i in 0 ..< token.count {
                        let byte = bytes.advanced(by: i).pointee
                        tokenString = tokenString.appendingFormat("%02x", Int32(byte))
                    }
                }
                
                let appVersionString = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? ""))"
                
                let langCode = NSLocale.preferredLanguages.first ?? "en"
                
                #if os(macOS)
                    let pInfo = ProcessInfo.processInfo
                    let systemVersion = pInfo.operatingSystemVersionString
                #else
                    let systemVersion = UIDevice.current.systemVersion
                #endif
                
                var appSandbox: Api.Bool = .boolFalse
                #if DEBUG
                    appSandbox = .boolTrue
                #endif
                
                return network.request(Api.functions.account.registerDevice(tokenType: 1, token: tokenString, deviceModel: "iPhome Simulator", systemVersion: systemVersion, appVersion: appVersionString, appSandbox: appSandbox, langCode: langCode))
                    |> retryRequest
                    |> mapToSignal { _ -> Signal<Void, NoError> in
                        return .complete()
                    }
            }
        self.notificationTokenDisposable.set(appliedNotificationToken.start())
        
        let serviceTasksMasterBecomeMaster = shouldBeServiceTaskMaster.get()
            |> distinctUntilChanged
            |> deliverOn(Queue.concurrentDefaultQueue())
        
        self.becomeMasterDisposable.set(serviceTasksMasterBecomeMaster.start(next: { [weak self] value in
            if let strongSelf = self, (value == .now || value == .always) {
                strongSelf.postbox.becomeMasterClient()
            }
        }))
        
        let shouldBeMaster = combineLatest(shouldBeServiceTaskMaster.get(), postbox.isMasterClient())
            |> map { [weak self] shouldBeMaster, isMaster -> Bool in
                if shouldBeMaster == .always && !isMaster {
                    self?.postbox.becomeMasterClient()
                }
                return (shouldBeMaster == .now || shouldBeMaster == .always) && isMaster
            }
            |> distinctUntilChanged
        
        self.network.shouldKeepConnection.set(shouldBeMaster)
        
        let serviceTasksMaster = shouldBeMaster
            |> deliverOn(Queue.concurrentDefaultQueue())
            |> mapToSignal { [weak self] value -> Signal<Void, NoError> in
                if let strongSelf = self, value {
                    trace("Account", what: "Became master")
                    return managedServiceViews(network: strongSelf.network, postbox: strongSelf.postbox, stateManager: strongSelf.stateManager, pendingMessageManager: strongSelf.pendingMessageManager)
                } else {
                    trace("Account", what: "Resigned master")
                    return .never()
                }
            }
        self.managedServiceViewsDisposable.set(serviceTasksMaster.start())
        
        let updatedPresence = self.shouldKeepOnlinePresence.get()
            |> distinctUntilChanged
            |> mapToSignal { [weak self] online -> Signal<Void, NoError> in
                if let strongSelf = self {
                    if online {
                        let delayRequest: Signal<Void, NoError> = .complete() |> delay(60.0, queue: Queue.concurrentDefaultQueue())
                        let pushStatusOnce = strongSelf.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
                            |> retryRequest
                            |> mapToSignal { _ -> Signal<Void, NoError> in return .complete() }
                        let pushStatusRepeatedly = (pushStatusOnce |> then(delayRequest)) |> restart
                        let peerId = strongSelf.peerId
                        let updatePresenceLocally = strongSelf.postbox.modify { modifier -> Void in
                            let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970 + 60.0 * 60.0 * 24.0 * 356.0
                            modifier.updatePeerPresences([peerId: TelegramUserPresence(status: .present(until: Int32(timestamp)))])
                        }
                        return combineLatest(pushStatusRepeatedly, updatePresenceLocally)
                            |> mapToSignal { _ -> Signal<Void, NoError> in return .complete() }
                    } else {
                        let pushStatusOnce = strongSelf.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
                            |> retryRequest
                            |> mapToSignal { _ -> Signal<Void, NoError> in return .complete() }
                        let peerId = strongSelf.peerId
                        let updatePresenceLocally = strongSelf.postbox.modify { modifier -> Void in
                            let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970 - 1.0
                            modifier.updatePeerPresences([peerId: TelegramUserPresence(status: .present(until: Int32(timestamp)))])
                        }
                        return combineLatest(pushStatusOnce, updatePresenceLocally)
                            |> mapToSignal { _ -> Signal<Void, NoError> in return .complete() }
                    }
                    
                    return .complete()
                } else {
                    return .complete()
                }
            }
        self.updatedPresenceDisposable.set(updatedPresence.start())
    }
    
    deinit {
        self.managedContactsDisposable.dispose()
        self.managedStickerPacksDisposable.dispose()
        self.notificationTokenDisposable.dispose()
        self.managedServiceViewsDisposable.dispose()
        self.updatedPresenceDisposable.dispose()
    }
    
    public func currentNetworkStats() -> Signal<MTNetworkUsageManagerStats, NoError> {
        return Signal { subscriber in
            let manager = MTNetworkUsageManager(info: MTNetworkUsageCalculationInfo(filePath: accountNetworkUsageInfoPath(basePath: self.basePath)))!
            manager.currentStats().start(next: { next in
                if let stats = next as? MTNetworkUsageManagerStats {
                    subscriber.putNext(stats)
                }
                subscriber.putCompletion()
            }, error: nil, completed: nil)
            
            return EmptyDisposable
        }
    }
}

public func setupAccount(_ account: Account, fetchCachedResourceRepresentation: ((_ account: Account, _ resource: MediaResource, _ resourceData: MediaResourceData, _ representation: CachedMediaResourceRepresentation) -> Signal<CachedMediaResourceRepresentationResult, NoError>)? = nil) {
    account.postbox.mediaBox.fetchResource = { [weak account] resource, range -> Signal<MediaResourceDataFetchResult, NoError> in
        if let strongAccount = account {
            return fetchResource(account: strongAccount, resource: resource, range: range)
        } else {
            return .never()
        }
    }
    
    account.postbox.mediaBox.fetchCachedResourceRepresentation = { [weak account] resource, resourceData, representation in
        if let strongAccount = account, let fetchCachedResourceRepresentation = fetchCachedResourceRepresentation {
            return fetchCachedResourceRepresentation(strongAccount, resource, resourceData, representation)
        } else {
            return .never()
        }
    }
    
    account.managedContactsDisposable.set(manageContacts(network: account.network, postbox: account.postbox).start())
    account.managedStickerPacksDisposable.set(manageStickerPacks(network: account.network, postbox: account.postbox).start())
    
    /*account.network.request(Api.functions.help.getScheme(version: 0)).start(next: { result in
        if case let .scheme(text, _, _, _) = result {
            print("\(text)")
        }
    })*/
}
