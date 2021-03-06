//
//  ResourceDownloader.swift
//  SevenPlusH
//
//  Created by Michael Peng on 10/22/18.
//  Copyright © 2018 PreMatch. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

public enum DownloadError: Error {
    case badConnection
    case unauthorized
    case noSuchSchedule
    case malformedSchedule(ParseError)
    case malformedCalendar(ParseError)
    case other(Error)
}

public typealias HTTPErrorHandler = (HTTPURLResponse?, Error) -> Void

public struct Downloader {
    static let loginEndpoint = "https://prematch.org/api/login"
    static let scheduleReadEndpoint = "https://prematch.org/api/schedule"
    static let calendarDefinitionEndpoint = "https://prematch.org/static/calendar.json"
    
    public init() {
    }
    
    private func classifyError(_ res: HTTPURLResponse?, _ err: Error) -> DownloadError {
        guard let res = res else {
            return DownloadError.badConnection
        }
        switch res.statusCode {
        case 401:
            return DownloadError.unauthorized
        case 404:
            return DownloadError.noSuchSchedule
        default:
            return DownloadError.other(err)
        }
    }
    
    private func login(idToken: String, onSuccess: @escaping () -> Void,
                       onFailure: @escaping HTTPErrorHandler) -> Void {
        Alamofire.request(Downloader.loginEndpoint, parameters: ["id_token": idToken])
            .validate()
            .responseJSON { response in
                switch response.result {
                case .failure(let error):
                    onFailure(response.response, error)
                case .success:
                    onSuccess()
                }
        }
    }
    
    public func readScheduleJSON(handle: String,
                                 processSchedule: @escaping (JSON) -> Void,
                                 onFailure: @escaping HTTPErrorHandler) -> Void {
        Alamofire.request(Downloader.scheduleReadEndpoint, parameters: ["handle": handle])
            .validate()
            .responseJSON { response in
                switch response.result {
                case .failure(let error):
                    onFailure(response.response, error)
                case .success(let value):
                    processSchedule(JSON(value))
                }
        }
    }
    
    public func readCalendarJSON(onSuccess: @escaping (JSON) -> Void,
                                 onFailure: @escaping HTTPErrorHandler) -> Void {
        Alamofire.request(Downloader.calendarDefinitionEndpoint)
            .validate()
            .responseJSON { response in
                switch response.result {
                case .failure(let error):
                    onFailure(response.response, error)
                case .success(let value):
                    onSuccess(JSON(value))
                }
        }
    }
    
    public func storeSchedule(googleIdToken: String, handle: String,
                         calendar: SphCalendar,
                         onSuccess: @escaping (SphSchedule) -> Void,
                         onFailure: @escaping (DownloadError) -> Void) {
        login(idToken: googleIdToken, onSuccess: {
            self.readScheduleJSON(handle: handle,
                                  processSchedule: {
                                    do {
                                        let schedule = try SphSchedule.from(json: $0, calendar: calendar)
                                        ResourceProvider.store(schedule: schedule)
                                        onSuccess(schedule)
                                    } catch {
                                        onFailure(DownloadError.malformedSchedule(error as! ParseError))
                                    }
                                    
            },
                                  onFailure: { onFailure(self.classifyError($0, $1)) })
        }, onFailure: { onFailure(self.classifyError($0, $1)) })
        
    }
    
    public func storeCalendar(onSuccess: @escaping (SphCalendar) -> Void,
                         onFailure: @escaping (DownloadError) -> Void) -> Void {
        readCalendarJSON(onSuccess: {
            do {
                try ResourceProvider.store(calendar: $0)
                onSuccess(ResourceProvider.calendar()!)
            } catch {
                onFailure(DownloadError.malformedCalendar(error as! ParseError))
            }
        }, onFailure: { res, err in
            onFailure(self.classifyError(res, err))
        })
    }
}
