import SwiftUI

struct MovementDemonstration: View {
    var movement: Movement

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let demo = MotionDiagram.builtIn[movement.id] {
                HStack(spacing: 8) {
                    pose(demo.start, on: demo.support, label: "demo.start", id: "start")
                    Image(systemName: "arrow.right").font(.caption).accessibilityHidden(true)
                    pose(demo.end, on: demo.support,
                         label: movement.unit == .seconds ? "demo.hold" : "demo.end", id: "end")
                }
                .padding(8)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 9))
                ForEach(1...3, id: \.self) { index in
                    tip(L.t("\(movement.name).tip.\(index)"), index: index)
                }
            } else {
                tip(movement.instruction.isEmpty ? L.t("demo.custom") : movement.instruction, index: 1)
            }
        }
        .padding(10)
        .background(Palette.tint, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("demo.card.\(movement.id)")
    }

    private func pose(_ pose: FigurePose, on support: [[Joint]], label: String, id: String) -> some View {
        VStack(spacing: 2) {
            FigureDrawing(pose: pose, support: support)
                .aspectRatio(120 / 88.0, contentMode: .fit)
                .frame(maxWidth: 144)
                .accessibilityHidden(true)
            Text(L.t(label)).font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("demo.pose.\(id).\(movement.id)")
    }

    private func tip(_ text: String, index: Int) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "circle.fill").font(.system(size: 4)).accessibilityHidden(true)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("demo.tip.\(movement.id).\(index)")
    }
}

private typealias Joint = (x: CGFloat, y: CGFloat)

private struct FigurePose {
    let head: Joint
    let shoulder: Joint
    let hip: Joint
    let elbow: Joint
    let hand: Joint
    let knee: Joint
    let foot: Joint
    var backLeg: [Joint] = []
}

private struct FigureDrawing: View {
    var pose: FigurePose
    var support: [[Joint]]

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 120
            let center = CGPoint(x: pose.head.x * scale, y: pose.head.y * scale)
            let radius = 5.5 * scale
            let torso = [pose.head, pose.shoulder, pose.hip]
            let arm = [pose.shoulder, pose.elbow, pose.hand]
            let leg = [pose.hip, pose.knee, pose.foot]
            ZStack {
                lines(support, scale: scale)
                    .stroke(Palette.muted, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                lines([pose.backLeg], scale: scale)
                    .stroke(Palette.action.opacity(0.55),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                lines([torso, arm, leg], scale: scale)
                    .stroke(Palette.action, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                let head = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                  width: 2 * radius, height: 2 * radius))
                head.fill(Palette.paper)
                head.stroke(Palette.action, lineWidth: 2)
            }
        }
    }

    private func lines(_ segments: [[Joint]], scale: CGFloat) -> Path {
        Path { path in
            for segment in segments {
                let points = segment.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
                if points.count > 1 { path.addLines(points) }
            }
        }
    }
}

private struct MotionDiagram {
    let start: FigurePose
    let end: FigurePose
    var support: [[Joint]] = [[(10, 76), (110, 76)]]

    static let builtIn: [String: Self] = [
        "builtin.push.0": .init(
            start: .init(head: (70, 18), shoulder: (63, 29), hip: (49, 49),
                         elbow: (81, 32), hand: (101, 34), knee: (37, 63), foot: (28, 76)),
            end: .init(head: (89, 20), shoulder: (82, 30), hip: (59, 49),
                       elbow: (80, 46), hand: (101, 34), knee: (43, 63), foot: (28, 76)),
            support: [[(10, 76), (101, 76), (101, 11)]]),
        "builtin.push.1": .init(
            start: .init(head: (84, 21), shoulder: (75, 28), hip: (52, 49),
                         elbow: (81, 34), hand: (89, 42), knee: (37, 62), foot: (22, 76)),
            end: .init(head: (99, 30), shoulder: (87, 36), hip: (59, 53),
                       elbow: (75, 45), hand: (89, 42), knee: (41, 64), foot: (22, 76)),
            support: [[(10, 76), (110, 76)], [(84, 76), (84, 42), (109, 42), (109, 76)]]),
        "builtin.push.2": .init(
            start: .init(head: (89, 38), shoulder: (77, 44), hip: (52, 57),
                         elbow: (79, 60), hand: (80, 76), knee: (37, 66), foot: (21, 76)),
            end: .init(head: (97, 57), shoulder: (85, 62), hip: (55, 67),
                       elbow: (69, 64), hand: (80, 76), knee: (37, 71), foot: (21, 76))),
        "builtin.push.3": .init(
            start: .init(head: (90, 42), shoulder: (77, 47), hip: (52, 49),
                         elbow: (79, 61), hand: (80, 76), knee: (33, 49), foot: (17, 50)),
            end: .init(head: (98, 58), shoulder: (85, 63), hip: (55, 57),
                       elbow: (69, 64), hand: (80, 76), knee: (35, 53), foot: (17, 50)),
            support: [[(10, 76), (110, 76)], [(12, 76), (12, 50), (29, 50), (29, 76)]]),
        "builtin.pull.0": .init(
            start: .init(head: (57, 29), shoulder: (62, 39), hip: (62, 56),
                         elbow: (63, 25), hand: (66, 12), knee: (63, 66), foot: (69, 76)),
            end: .init(head: (56, 34), shoulder: (62, 44), hip: (62, 60),
                       elbow: (64, 28), hand: (66, 12), knee: (64, 69), foot: (72, 67)),
            support: [[(36, 12), (89, 12)], [(10, 76), (110, 76)]]),
        "builtin.pull.1": .init(
            start: .init(head: (55, 35), shoulder: (62, 45), hip: (58, 60),
                         elbow: (64, 33), hand: (66, 20), knee: (69, 66), foot: (78, 67)),
            end: .init(head: (60, 15), shoulder: (58, 26), hip: (58, 46),
                       elbow: (65, 40), hand: (66, 20), knee: (66, 57), foot: (78, 67)),
            support: [[(36, 20), (89, 20)], [(10, 76), (110, 76)],
                      [(70, 76), (70, 67), (89, 67), (89, 76)]]),
        "builtin.pull.2": .init(
            start: .init(head: (60, 13), shoulder: (58, 24), hip: (60, 44),
                         elbow: (66, 37), hand: (67, 19), knee: (62, 55), foot: (70, 66)),
            end: .init(head: (57, 38), shoulder: (62, 47), hip: (63, 62),
                       elbow: (65, 33), hand: (67, 19), knee: (64, 69), foot: (71, 72)),
            support: [[(36, 19), (89, 19)]]),
        "builtin.pull.3": .init(
            start: .init(head: (56, 37), shoulder: (62, 48), hip: (61, 65),
                         elbow: (65, 33), hand: (67, 19), knee: (61, 73), foot: (65, 79)),
            end: .init(head: (60, 13), shoulder: (58, 24), hip: (60, 46),
                       elbow: (66, 37), hand: (67, 19), knee: (61, 58), foot: (65, 69)),
            support: [[(36, 19), (89, 19)]]),
        "builtin.squat.0": .init(
            start: .init(head: (51, 30), shoulder: (47, 41), hip: (40, 57),
                         elbow: (56, 49), hand: (68, 46), knee: (63, 58), foot: (66, 76)),
            end: .init(head: (63, 14), shoulder: (61, 25), hip: (60, 46),
                       elbow: (66, 37), hand: (73, 48), knee: (63, 61), foot: (66, 76)),
            support: [[(10, 76), (110, 76)], [(25, 76), (25, 58), (49, 58), (49, 76)], [(25, 36), (25, 58)]]),
        "builtin.squat.1": .init(
            start: .init(head: (63, 14), shoulder: (61, 25), hip: (60, 46),
                         elbow: (66, 37), hand: (73, 48), knee: (63, 61), foot: (66, 76)),
            end: .init(head: (57, 29), shoulder: (50, 39), hip: (39, 57),
                       elbow: (63, 39), hand: (76, 38), knee: (64, 57), foot: (66, 76)),
            support: [[(10, 76), (110, 76)], [(25, 76), (25, 58), (49, 58), (49, 76)], [(25, 36), (25, 58)]]),
        "builtin.squat.2": .init(
            start: .init(head: (63, 14), shoulder: (61, 25), hip: (60, 46),
                         elbow: (66, 37), hand: (73, 48), knee: (63, 61), foot: (66, 76)),
            end: .init(head: (60, 36), shoulder: (52, 46), hip: (40, 63),
                       elbow: (66, 43), hand: (79, 39), knee: (67, 58), foot: (66, 76))),
        "builtin.squat.3": .init(
            start: .init(head: (57, 14), shoulder: (55, 25), hip: (54, 46),
                         elbow: (58, 36), hand: (58, 44), knee: (69, 60), foot: (82, 76),
                         backLeg: [(54, 46), (41, 61), (26, 76)]),
            end: .init(head: (60, 31), shoulder: (58, 41), hip: (55, 59),
                       elbow: (60, 49), hand: (61, 57), knee: (80, 59), foot: (82, 76),
                       backLeg: [(55, 59), (46, 73), (26, 76)])),
        "builtin.hold.0": .init(
            start: .init(head: (83, 15), shoulder: (80, 27), hip: (77, 46),
                         elbow: (90, 35), hand: (101, 36), knee: (74, 61), foot: (70, 76)),
            end: .init(head: (75, 20), shoulder: (67, 31), hip: (52, 49),
                       elbow: (84, 33), hand: (101, 36), knee: (41, 63), foot: (30, 76)),
            support: [[(10, 76), (101, 76), (101, 11)]]),
        "builtin.hold.1": .init(
            start: .init(head: (73, 17), shoulder: (68, 28), hip: (57, 47),
                         elbow: (77, 35), hand: (90, 44), knee: (56, 63), foot: (54, 76)),
            end: .init(head: (86, 23), shoulder: (75, 31), hip: (53, 49),
                       elbow: (81, 37), hand: (90, 44), knee: (37, 63), foot: (22, 76)),
            support: [[(10, 76), (110, 76)], [(85, 76), (85, 44), (108, 44), (108, 76)]]),
        "builtin.hold.2": .init(
            start: .init(head: (84, 43), shoulder: (73, 53), hip: (57, 57),
                         elbow: (74, 74), hand: (94, 74), knee: (54, 76), foot: (32, 76)),
            end: .init(head: (86, 45), shoulder: (74, 53), hip: (54, 65),
                       elbow: (74, 74), hand: (94, 74), knee: (36, 76), foot: (18, 76))),
        "builtin.hold.3": .init(
            start: .init(head: (86, 45), shoulder: (74, 53), hip: (53, 58),
                         elbow: (74, 74), hand: (94, 74), knee: (40, 76), foot: (20, 76)),
            end: .init(head: (86, 45), shoulder: (74, 53), hip: (52, 60),
                       elbow: (74, 74), hand: (94, 74), knee: (34, 67), foot: (19, 76)))
    ]
}
