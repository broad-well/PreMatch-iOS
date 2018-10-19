//
//  DefinitionReader.swift
//  SevenPlusH
//
//  Created by Michael Peng on 10/15/18.
//  Copyright © 2018 PreMatch. All rights reserved.
//

import Foundation
import SwiftyJSON

enum ParseError: Error {
  case missingField(String)
  case invalidFormat(fieldType: String, invalidValue: String)
    case outOfRange(fieldType: String, invalidValue: String)
}

func parseISODate(_ iso: String,
                        timezone: TimeZone = TimeZone(identifier: "America/New_York")!) throws -> Date {
  let formatter = ISO8601DateFormatter()
  formatter.timeZone = TimeZone(identifier: "America/New_York")
  formatter.formatOptions = .withFullDate
  
  guard let date = formatter.date(from: iso) else {
    throw ParseError.invalidFormat(fieldType: "Date", invalidValue: iso)
  }
  return date
}

extension Time {
    // [10, 20] -> 10:20
    static func fromJSON(_ json: JSON) throws -> Time {
        let hour = json[0].uInt8
        let minute = json[1].uInt8
        
        if hour == nil || minute == nil {
            throw ParseError.invalidFormat(fieldType: "time", invalidValue: json.stringValue)
        }
        return Time(hour!, minute!)
    }
}

extension Period {
    // [[7, 20], [9, 10]]
    static func fromJSON(_ json: JSON) throws -> Period {
        let (start, end) = (json[0], json[1])
        
        return Period(from: try Time.fromJSON(start), to: try Time.fromJSON(end))
    }
}

public class DefinitionReader {  
  
  class func downloadJSON() throws -> JSON {
    let data = try Data(contentsOf: URL(string: "https://prematch.org/static/calendar.json")!)
    return JSON(data)
  }
  
  public class func read() throws -> SphCalendar {
    let json = try downloadJSON()
    let blocks = try requiredField("blocks", json["blocks"].array)
    let startDate = try parseISODate(try requiredField("start date", json["start_date"].string))
    let endDate = try parseISODate(try requiredField("end date", json["end_date"].string))
    let exclusions = try requiredField("exclusions", json["exclusions"].array)
    let overrides = try requiredField("overrides", json["overrides"].array)
    let dayBlocks = try requiredField("standard day blocks collection", json["day_blocks"].array).map { blocks in
        try requiredField("standard day block array", blocks.array).map {
            try requiredField("standard day block string", $0.string)
        }
    }
    
    return SphCalendar(
        name: try requiredField("definition name", json["name"].string),
        version: try requiredField("version", json["version"].double),
        blocks: blocks.map { $0.stringValue },
        cycleSize: try requiredField("cycle size", json["cycle_size"].uInt8),
        interval: DateInterval(start: startDate, end: endDate),
        exclusions: try exclusions.map { try parseExclusion($0, inDef: json) },
        overrides: try overrides.map { try parseExclusion($0, inDef: json) },
        standardPeriods: try readPeriods(from: json["periods"], name: "standard periods"),
        halfDayPeriods: try readPeriods(from: json["half_day_periods"], name: "half day periods"),
        examPeriods: try readPeriods(from: json["exam_day_periods"], name: "exam day periods"),
        dayBlocks: dayBlocks
    )
  }
  
    class func parseExclusion(_ json: JSON, inDef def: JSON) throws -> Exclusion {
    return try ExclusionParser.parse(json, fromDef: def)
  }
    
    private class func readPeriods(from json: JSON, name: String) throws -> [Period]{
        let periods: [JSON] = try requiredField(name, json.array)
        return try periods.map { try Period.fromJSON($0) }
    }
  
  
}