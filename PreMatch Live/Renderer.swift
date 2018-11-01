//
//  Renderer.swift
//  PreMatch Live
//
//  Created by Michael Peng on 10/20/18.
//  Copyright © 2018 PreMatch. All rights reserved.
//

import Foundation
import SevenPlusH

private var formatter = DateFormatter()
private func format(_ date: Date, long: Bool = false) -> String {
    formatter.dateFormat = (long ? "EEEE, " : "") + "MMM d, yyyy"
    return formatter.string(from: date)
}

private func relativeExpression(for target: Date, relativeTo now: Date) -> String? {
    if ahsCalendar.isDate(now.dayAfter(), inSameDayAs: target) {
        return "tomorrow"
    }
    let targetComps = ahsCalendar.dateComponents(in: ahsTimezone, from: target),
        nowComps = ahsCalendar.dateComponents(in: ahsTimezone, from: now)
    
    guard let targetWeek = targetComps.weekOfYear,
        let thisWeek = nowComps.weekOfYear else {
            return nil
    }
    
    if targetWeek == thisWeek + 1 {
        formatter.dateFormat = "EEEE"
        return "next " + formatter.string(from: target)
    }
    
    return nil
}

private protocol Handler {
    func applicable(_ date: Date, in calendar: SphCalendar) -> Bool
    func apply(_ date: Date,
               in calendar: SphCalendar,
               for schedule: SphSchedule?,
               to view: TodayViewController)
}

struct OutsideYearHandler: Handler {
    func applicable(_ date: Date, in calendar: SphCalendar) -> Bool {
        return !calendar.includes(date)
    }
    func apply(_ date: Date, in calendar: SphCalendar,
               for: SphSchedule?, to view: TodayViewController) {
        view.showUnavailable("Not in current school year")
    }
}

struct HolidayHandler: Handler {
    func applicable(_ date: Date, in calendar: SphCalendar) -> Bool {
        return calendar.includes(date) && !calendar.isSchoolDay(on: date)
    }
    func apply(_ date: Date, in calendar: SphCalendar,
               for: SphSchedule?, to view: TodayViewController) {
        let schoolDay = calendar.nextSchoolDay(after: date)!
        let day = try! calendar.day(on: date)
        
        view.show(
            title: "Today is \(day.description)",
            info: "Showing next school day\n\(format(schoolDay.date, long: true))")
        view.showSchoolDay(schoolDay, isToday: false)
    }
}

struct BeforeSchoolHandler: Handler {
    func applicable(_ date: Date, in calendar: SphCalendar) -> Bool {
        if calendar.isSchoolDay(on: date) {
            let day = try! calendar.day(on: date) as! SchoolDay
            return Time.fromDate(date)!.isBefore(day)
        }
        return false
    }
    
    func apply(_ date: Date, in calendar: SphCalendar,
               for schedule: SphSchedule?, to view: TodayViewController) {
        
        let day = try! calendar.day(on: date) as! SchoolDay
        let firstBlock = day.blocks.first
        let firstTeacher = (firstBlock == nil || schedule == nil) ?
            "Someone unknown" : (try? schedule?.teacher(for: firstBlock!)) ?? "H-block"
        
        view.show(
            title: "Next: \(firstTeacher ?? "Unknown")",
            info: "Block \(firstBlock ?? "?")\nGood morning")
        view.showSchoolDay(day, isToday: true)
    }
}

struct AfterSchoolHandler: Handler {
    func applicable(_ date: Date, in calendar: SphCalendar) -> Bool {
        if calendar.isSchoolDay(on: date) {
            let day = try! calendar.day(on: date) as! SchoolDay
            return Time.fromDate(date)!.isAfter(day)
        }
        return false
    }
    
    func apply(_ date: Date, in calendar: SphCalendar,
               for schedule: SphSchedule?, to view: TodayViewController) {
        
        let today = try! calendar.day(on: date) as! SchoolDay
        let day = calendar.nextSchoolDay(after: date)!
        let expr = relativeExpression(for: day.date, relativeTo: date)
        
        view.show(
            title: "Today was \(today.description)",
            info: "Showing next school day\n\(expr ?? format(day.date, long: true))")
        view.showSchoolDay(day, isToday: false)
    }
}

struct DuringSchoolHandler: Handler {
    func applicable(_ date: Date, in calendar: SphCalendar) -> Bool {
        if calendar.isSchoolDay(on: date) {
            let day = try! calendar.day(on: date) as! SchoolDay
            return Time.fromDate(date)!.isInside(day)
        }
        return false
    }
    
    func apply(_ date: Date, in calendar: SphCalendar,
               for schedule: SphSchedule?, to view: TodayViewController) {
        let day = try! calendar.day(on: date) as! SchoolDay
        let now: Time = Time.fromDate(date)!
        
        let currentPeriodIndex = day.periodIndex(at: now)
        let currentBlock = day.block(at: now)
        let currentTeacher = currentBlock == nil ? "Unknown" :
            (try? schedule?.teacher(for: currentBlock!)) ?? "Unknown"
        
        view.showSchoolDay(day, isToday: true)
        if currentPeriodIndex == UInt8(day.periods.count - 1) {
            // Last block
            view.show(title: "Now: \(currentTeacher ?? "Unknown")",
                info: "Block \(currentBlock!)\nThis is the last block!")
           return
        }
        
        let nextIndex = day.nextPeriodIndex(at: now)!
        let nextBlock = day.blocks[Int(nextIndex)]
        let nextTeacher = schedule == nil ? "Unknown" :
            (try? schedule?.teacher(for: nextBlock)) ?? "Unknown"
        
        if currentPeriodIndex == nil {
            view.show(title: "Go to \(nextTeacher ?? "Unknown")",
                info: "Block \(nextBlock)")
        } else {
            view.show(title: "Now: \(currentTeacher ?? "Unknown")",
                info: "Block \(currentBlock!)\nNext: Block \(nextBlock) with \(nextTeacher ?? "Unknown")")
        }
    }
}

struct Renderer {
    private let handlers: [Handler] = [
        OutsideYearHandler(),
        HolidayHandler(),
        BeforeSchoolHandler(),
        AfterSchoolHandler(),
        DuringSchoolHandler()
    ]
    private var calendar: SphCalendar
    private var schedule: SphSchedule?
    private let view: TodayViewController
    
    init(renderTo view: TodayViewController) throws {
        guard let calendar = ResourceProvider.calendar() else {
            throw ProviderError.noCalendarAvailable
        }
        self.calendar = calendar
        schedule = ResourceProvider.schedule()
        self.view = view
    }
    
    public func render() -> Bool {
        let date = Date()
        guard let handler = handlers.first(where: { $0.applicable(date, in: calendar) }) else {
            return false
        }
        handler.apply(date, in: calendar, for: schedule, to: view)
        return true
    }
}
