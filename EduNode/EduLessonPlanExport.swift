import Foundation
import CoreGraphics
import GNodeKit
#if canImport(UIKit)
import UIKit
#endif

struct EduLessonPlanContext: Sendable {
    let name: String
    let gradeMode: String
    let gradeMin: Int
    let gradeMax: Int
    let subject: String
    let studentCount: Int
    let lessonDurationMinutes: Int
    let periodRange: String
    let goalsText: String
    let modelID: String
    let teacherTeam: String
    let studentPriorKnowledgeLevel: String
    let studentMotivationLevel: String
    let studentSupportNotes: String
    let resourceConstraints: String

    init(file: GNodeWorkspaceFile) {
        self.name = file.name
        self.gradeMode = file.gradeMode
        self.gradeMin = file.gradeMin
        self.gradeMax = file.gradeMax
        self.subject = file.subject
        self.studentCount = file.studentCount
        self.lessonDurationMinutes = file.lessonDurationMinutes
        self.periodRange = file.periodRange
        self.goalsText = file.goalsText
        self.modelID = file.modelID
        self.teacherTeam = file.teacherTeam
        self.studentPriorKnowledgeLevel = file.studentPriorKnowledgeLevel
        self.studentMotivationLevel = file.studentMotivationLevel
        self.studentSupportNotes = file.studentSupportNotes
        self.resourceConstraints = file.resourceConstraints
    }
}

enum EduLessonPlanExporter {
    static func markdownData(context: EduLessonPlanContext, graphData: Data) -> Data? {
        markdown(context: context, graphData: graphData).data(using: .utf8)
    }

    static func pdfData(context: EduLessonPlanContext, graphData: Data) -> Data? {
        let renderedHTML = html(context: context, graphData: graphData)
        return renderPDF(markupHTML: renderedHTML, title: context.name)
    }

    static func html(context: EduLessonPlanContext, graphData: Data) -> String {
        let isChinese = prefersChineseUI
        guard let document = try? decodeDocument(from: graphData) else {
            let fallbackTitle = isChinese ? "教案导出失败" : "Lesson Plan Export Failed"
            let fallbackBody = isChinese
                ? "无法解析当前课程画布数据。"
                : "Unable to parse current course-canvas data."
            return """
            <!doctype html>
            <html><head><meta charset="utf-8"></head>
            <body><h1>\(fallbackTitle)</h1><p>\(fallbackBody)</p></body></html>
            """
        }

        let graph = ParsedGraph(document: document, isChinese: isChinese)
        let mainFlow = graph.mainFlowNodes
        let evaluation = graph.evaluationNodes
        let overviewRows = buildLessonOverviewRows(graph: graph, isChinese: isChinese)

        let fallbackCourseName = isChinese ? "未命名课程" : "Untitled Course"
        let courseName = nonEmpty(context.name, fallback: fallbackCourseName)
        let exportTime = Date().formatted(.dateTime.year().month().day().hour().minute())
        let gradeLabel = context.gradeMode == "age"
            ? (isChinese ? "年龄" : "Age")
            : (isChinese ? "年级" : "Grade")
        let gradeRange = "\(gradeLabel) \(context.gradeMin)-\(context.gradeMax)"
        let goals = splitMultilineItems(context.goalsText)
        let infoNA = isChinese ? "未设置" : "Not set"

        let infoRows = [
            (isChinese ? "学科" : "Subject", fallback(context.subject, isChinese: isChinese)),
            (isChinese ? "范围" : "Range", gradeRange),
            (isChinese ? "学生人数" : "Student Count", "\(context.studentCount)"),
            (isChinese ? "课时长度" : "Duration", "\(context.lessonDurationMinutes) \(isChinese ? "分钟" : "min")"),
            (isChinese ? "日期/场景" : "Date / Scene", fallback(context.periodRange, isChinese: isChinese)),
            (isChinese ? "教学模型" : "Model", fallback(context.modelID, isChinese: isChinese)),
            (isChinese ? "教师团队" : "Teaching Team", fallback(context.teacherTeam, isChinese: isChinese))
        ]
        let infoTableRows = infoRows.map { row in
            "<tr><th>\(escapeHTML(row.0))</th><td>\(escapeHTML(row.1))</td></tr>"
        }.joined()

        let learnerRows = [
            (isChinese ? "前测均值" : "Prior Assessment", fallbackPercent(context.studentPriorKnowledgeLevel, isChinese: isChinese)),
            (isChinese ? "作业完成率" : "Assignment Completion", fallbackPercent(context.studentMotivationLevel, isChinese: isChinese)),
            (isChinese ? "支持备注" : "Support Notes", fallback(context.studentSupportNotes, isChinese: isChinese)),
            (isChinese ? "资源约束" : "Resource Constraints", fallback(context.resourceConstraints, isChinese: isChinese))
        ]
        let learnerTableRows = learnerRows.map { row in
            "<tr><th>\(escapeHTML(row.0))</th><td>\(escapeHTML(row.1))</td></tr>"
        }.joined()

        let goalsHTML: String = {
            guard !goals.isEmpty else {
                return "<p class=\"muted\">\(escapeHTML(isChinese ? "未设置（建议至少设置 2-3 条可评估目标）" : "Not set (recommend at least 2-3 assessable goals)."))</p>"
            }
            let items = goals.map { "<li>\(escapeHTML($0))</li>" }.joined()
            return "<ol class=\"tight-list\">\(items)</ol>"
        }()

        let flowRows: String = {
            guard !overviewRows.isEmpty else {
                return "<tr><td colspan=\"5\" class=\"muted\">\(escapeHTML(isChinese ? "当前画布还没有可编排的知识环节。" : "No teachable knowledge stages found in current canvas."))</td></tr>"
            }
            return overviewRows.enumerated().map { index, row in
                let toolkitCell = row.toolkits.isEmpty
                    ? "-"
                    : row.toolkits.map { item in escapeHTML(item) }.joined(separator: "<br>")
                return """
                <tr>
                  <td>\(index + 1)</td>
                  <td>\(escapeHTML(row.stepTitle))</td>
                  <td>\(escapeHTML(row.knowledge))</td>
                  <td>\(toolkitCell)</td>
                  <td>\(escapeHTML(row.coreContent))</td>
                </tr>
                """
            }.joined()
        }()

        let stepsHTML: String = {
            guard !mainFlow.isEmpty else {
                return "<p class=\"muted\">\(escapeHTML(isChinese ? "暂无可展开的课堂环节。" : "No lesson stages available for detailed planning."))</p>"
            }
            let mainIDs = Set(mainFlow.map(\.id))
            return mainFlow.enumerated().map { index, node in
                let inputs = graph.incomingTitles(for: node.id, limitedTo: mainIDs)
                let inputText = inputs.isEmpty
                    ? (node.isKnowledge
                        ? (isChinese ? "可独立开展，无明显前置限制。" : "Can run independently without strict prerequisite.")
                        : (isChinese ? "建议在前序知识或活动后实施。" : "Recommended after preceding knowledge or activity stage."))
                    : inputs.joined(separator: " / ")

                let processText = node.isKnowledge
                    ? (isChinese ? "围绕该知识点开展讲授、提问与理解巩固。" : "Deliver explanation, questioning and consolidation around this knowledge point.")
                    : node.formProcessSummary

                let methodRows: String = {
                    guard !node.detailedFieldLines.isEmpty else { return "" }
                    let rows = node.detailedFieldLines.map { "<li>\(escapeHTML($0))</li>" }.joined()
                    return """
                    <div class="subsec">
                      <div class="subsec-title">\(escapeHTML(isChinese ? "实施要点" : "Implementation Notes"))</div>
                      <ul class="tight-list">\(rows)</ul>
                    </div>
                    """
                }()

                return """
                <article class="step-card">
                  <div class="step-head">
                    <div class="step-index">\(isChinese ? "步骤" : "Step") \(index + 1)</div>
                    <h3>\(escapeHTML(node.title))</h3>
                  </div>
                  <table class="kv">
                    <tr><th>\(escapeHTML(isChinese ? "环节定位" : "Stage Positioning"))</th><td>\(escapeHTML(node.kindLabel))</td></tr>
                    <tr><th>\(escapeHTML(isChinese ? "教学方式/认知层级" : "Teaching Mode / Cognitive Level"))</th><td>\(escapeHTML(node.methodOrLevelLabel.isEmpty ? "-" : node.methodOrLevelLabel))</td></tr>
                    <tr><th>\(escapeHTML(isChinese ? "前后衔接" : "Prerequisite & Transition"))</th><td>\(escapeHTML(inputText))</td></tr>
                    <tr><th>\(escapeHTML(isChinese ? "教师实施" : "Teacher Action"))</th><td>\(escapeHTML(processText))</td></tr>
                    <tr><th>\(escapeHTML(isChinese ? "学习产出" : "Learner Outcome"))</th><td>\(escapeHTML(node.shortSummary))</td></tr>
                  </table>
                  \(methodRows)
                </article>
                """
            }.joined()
        }()

        let evalRows: String = {
            guard !evaluation.isEmpty else {
                return "<tr><td colspan=\"3\" class=\"muted\">\(escapeHTML(isChinese ? "当前未形成完整评价环节，建议补充评价指标与汇总策略。" : "No complete assessment section detected; consider adding metrics and summary strategy."))</td></tr>"
            }
            return evaluation.map { node in
                "<tr><td>\(escapeHTML(node.title))</td><td>\(escapeHTML(node.kindLabel))</td><td>\(escapeHTML(node.shortSummary))</td></tr>"
            }.joined()
        }()

        let extensionNodes = mainFlow.filter(\.isAfterClassNode)
        let extensionHTML: String = {
            if extensionNodes.isEmpty {
                return "<p class=\"muted\">\(escapeHTML(isChinese ? "当前未识别到明确课后延伸活动。" : "No explicit after-class extension activity detected."))</p>"
            }
            let items = extensionNodes.map { "<li><strong>\(escapeHTML($0.title))</strong>：\(escapeHTML($0.shortSummary))</li>" }.joined()
            return "<ul class=\"tight-list\">\(items)</ul>"
        }()

        let reflectionPrompts = [
            isChinese ? "哪些课堂环节衔接最顺畅？哪些环节需要补充材料或调整时长？" : "Which stage transitions were smooth, and which stages need more materials or time adjustment?",
            isChinese ? "学生在哪个环节出现明显困难？原因是什么？" : "At which stage did learners struggle most, and why?",
            isChinese ? "下一次迭代优先优化哪一段课堂流程？" : "Which part of the lesson flow should be prioritized in the next iteration?"
        ]
        let reflectionHTML = reflectionPrompts.map { "<li>\(escapeHTML($0))</li>" }.joined()

        let html = """
        <!doctype html>
        <html lang="\(isChinese ? "zh-Hans" : "en")">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root { color-scheme: light; }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 24px;
              background: #eef2f8;
              color: #1a2332;
              font: 14px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", Arial, sans-serif;
            }
            .page {
              width: 100%;
              max-width: 820px;
              margin: 0 auto;
              background: #fff;
              border-radius: 18px;
              box-shadow: 0 18px 46px rgba(18, 36, 72, 0.12);
              padding: 26px 28px 30px;
            }
            .hero {
              border: 1px solid #dfe7f5;
              background: linear-gradient(135deg, #f5f8ff 0%, #eef8ff 100%);
              border-radius: 14px;
              padding: 16px 18px;
              margin-bottom: 18px;
            }
            .hero h1 {
              margin: 0 0 8px;
              font-size: 26px;
              line-height: 1.22;
              color: #132038;
            }
            .meta {
              display: flex;
              flex-wrap: wrap;
              gap: 8px 10px;
              margin: 0;
              padding: 0;
              list-style: none;
            }
            .meta li {
              background: rgba(20, 46, 90, 0.08);
              border-radius: 999px;
              padding: 4px 10px;
              font-size: 12px;
              color: #2a3958;
            }
            h2 {
              margin: 20px 0 10px;
              font-size: 18px;
              line-height: 1.3;
              color: #172947;
              border-left: 4px solid #4a79ff;
              padding-left: 10px;
            }
            h3 {
              margin: 0;
              font-size: 16px;
              line-height: 1.35;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              border: 1px solid #dfe6f3;
              border-radius: 12px;
              overflow: hidden;
              margin: 10px 0 12px;
              table-layout: auto;
            }
            th, td {
              border: 1px solid #e4eaf5;
              padding: 8px 10px;
              vertical-align: top;
              word-wrap: break-word;
            }
            th {
              background: #f4f7fc;
              color: #243756;
              font-weight: 600;
              text-align: left;
            }
            .flow th, .flow td { font-size: 13px; }
            .overview { table-layout: fixed; }
            .overview col.c-index { width: 8%; }
            .overview col.c-step { width: 20%; }
            .overview col.c-knowledge { width: 24%; }
            .overview col.c-toolkit { width: 18%; }
            .overview col.c-core { width: 30%; }
            .overview th:first-child,
            .overview td:first-child {
              text-align: center;
              white-space: nowrap;
            }
            .overview td { line-height: 1.45; }
            .muted {
              color: #6f7e97;
              font-style: italic;
            }
            .tight-list {
              margin: 6px 0 10px 20px;
              padding: 0;
            }
            .tight-list li { margin: 4px 0; }
            .steps {
              display: grid;
              grid-template-columns: 1fr;
              gap: 12px;
              margin-top: 8px;
            }
            .step-card {
              border: 1px solid #dfe7f5;
              border-left: 4px solid #4a79ff;
              border-radius: 12px;
              padding: 10px 12px 12px;
              background: #fcfdff;
              page-break-inside: avoid;
            }
            .step-head {
              display: flex;
              flex-direction: column;
              gap: 4px;
              margin-bottom: 8px;
            }
            .step-index {
              font-size: 12px;
              font-weight: 700;
              color: #3a5bc6;
            }
            .kv th { width: 132px; }
            .subsec { margin-top: 8px; }
            .subsec-title {
              font-weight: 700;
              font-size: 13px;
              margin-bottom: 2px;
              color: #2c4068;
            }
            @media print {
              @page { size: A4; margin: 14mm 12mm; }
              body { background: #fff; padding: 0; }
              .page {
                max-width: none;
                border-radius: 0;
                box-shadow: none;
                padding: 0;
              }
              h2 { page-break-after: avoid; }
            }
          </style>
        </head>
        <body>
          <main class="page">
            <section class="hero">
              <h1>\(escapeHTML(courseName)) · \(isChinese ? "教案" : "Lesson Plan")</h1>
              <ul class="meta">
                <li>\(escapeHTML(isChinese ? "导出时间" : "Exported At")): \(escapeHTML(exportTime))</li>
                <li>\(escapeHTML(isChinese ? "来源文件" : "Source File")): \(escapeHTML(courseName))</li>
                <li>\(escapeHTML(isChinese ? "关键信息" : "Core Context")): \(escapeHTML(infoRows.map(\.1).contains(infoNA) ? (isChinese ? "部分缺失" : "Partially Missing") : (isChinese ? "完整" : "Complete")))</li>
              </ul>
            </section>

            <section>
              <h2>\(escapeHTML(isChinese ? "1. 课程概览" : "1. Course Snapshot"))</h2>
              <table class="kv">\(infoTableRows)</table>
            </section>

            <section>
              <h2>\(escapeHTML(isChinese ? "2. 教学目标" : "2. Teaching Goals"))</h2>
              \(goalsHTML)
            </section>

            <section>
              <h2>\(escapeHTML(isChinese ? "3. 学生与支持信息" : "3. Learner Profile & Support"))</h2>
              <table class="kv">\(learnerTableRows)</table>
            </section>

            <section>
              <h2>\(escapeHTML(isChinese ? "4. 课堂流程总览" : "4. Lesson Flow Overview"))</h2>
              <table class="flow overview">
                <colgroup>
                  <col class="c-index">
                  <col class="c-step">
                  <col class="c-knowledge">
                  <col class="c-toolkit">
                  <col class="c-core">
                </colgroup>
                <thead>
                  <tr>
                    <th>Index</th>
                    <th>Step</th>
                    <th>Knowledge</th>
                    <th>Toolkit</th>
                    <th>Core Content</th>
                  </tr>
                </thead>
                <tbody>\(flowRows)</tbody>
              </table>
            </section>

            <section>
              <h2>\(escapeHTML(isChinese ? "5. 分环节教学设计" : "5. Stage-by-stage Teaching Design"))</h2>
              <div class="steps">\(stepsHTML)</div>
            </section>

            <section>
              <h2>\(escapeHTML(isChinese ? "6. 评价与证据" : "6. Assessment & Evidence"))</h2>
              <table class="flow">
                <thead>
                  <tr>
                    <th>\(escapeHTML(isChinese ? "评价环节" : "Assessment Stage"))</th>
                    <th>\(escapeHTML(isChinese ? "评价方式" : "Assessment Approach"))</th>
                    <th>\(escapeHTML(isChinese ? "证据与说明" : "Evidence & Notes"))</th>
                  </tr>
                </thead>
                <tbody>\(evalRows)</tbody>
              </table>
            </section>

            <section>
              <h2>\(escapeHTML(isChinese ? "7. 课后延伸与反思" : "7. Extension & Reflection"))</h2>
              \(extensionHTML)
              <div class="subsec">
                <div class="subsec-title">\(escapeHTML(isChinese ? "课后反思问题" : "Post-lesson Reflection Prompts"))</div>
                <ol class="tight-list">\(reflectionHTML)</ol>
              </div>
            </section>
          </main>
        </body>
        </html>
        """

        return html
    }

    static func markdown(context: EduLessonPlanContext, graphData: Data) -> String {
        let isChinese = prefersChineseUI
        guard let document = try? decodeDocument(from: graphData) else {
            return isChinese
                ? "# 教案导出失败\n\n无法解析当前课程画布数据。"
                : "# Lesson Plan Export Failed\n\nUnable to parse current course-canvas data."
        }

        let graph = ParsedGraph(document: document, isChinese: isChinese)
        let mainFlow = graph.mainFlowNodes
        let evaluation = graph.evaluationNodes
        let overviewRows = buildLessonOverviewRows(graph: graph, isChinese: isChinese)

        let fallbackCourseName = isChinese ? "未命名课程" : "Untitled Course"
        let courseName = nonEmpty(context.name, fallback: fallbackCourseName)
        let exportTime = Date().formatted(.dateTime.year().month().day().hour().minute())
        let gradeLabel = context.gradeMode == "age"
            ? (isChinese ? "年龄" : "Age")
            : (isChinese ? "年级" : "Grade")
        let gradeRange = "\(gradeLabel) \(context.gradeMin)-\(context.gradeMax)"
        let goals = splitMultilineItems(context.goalsText)

        var lines: [String] = []
        lines.append("# \(courseName) · \(isChinese ? "教案" : "Lesson Plan")")
        lines.append("")
        lines.append("- \(isChinese ? "导出时间" : "Exported At"): \(exportTime)")
        lines.append("- \(isChinese ? "文件" : "Source File"): \(courseName)")
        lines.append("")

        lines.append("## \(isChinese ? "1. 课程概览" : "1. Course Snapshot")")
        lines.append("| \(isChinese ? "项目" : "Item") | \(isChinese ? "内容" : "Value") |")
        lines.append("|---|---|")
        lines.append("| \(isChinese ? "学科" : "Subject") | \(fallback(context.subject, isChinese: isChinese)) |")
        lines.append("| \(isChinese ? "范围" : "Range") | \(gradeRange) |")
        lines.append("| \(isChinese ? "学生人数" : "Student Count") | \(context.studentCount) |")
        lines.append("| \(isChinese ? "课时长度" : "Duration") | \(context.lessonDurationMinutes) \(isChinese ? "分钟" : "min") |")
        lines.append("| \(isChinese ? "日期/场景" : "Date / Scene") | \(fallback(context.periodRange, isChinese: isChinese)) |")
        lines.append("| \(isChinese ? "教学模型" : "Model") | \(fallback(context.modelID, isChinese: isChinese)) |")
        lines.append("| \(isChinese ? "教师团队" : "Teaching Team") | \(fallback(context.teacherTeam, isChinese: isChinese)) |")
        lines.append("")

        lines.append("## \(isChinese ? "2. 教学目标" : "2. Teaching Goals")")
        if goals.isEmpty {
            lines.append("- \(isChinese ? "未设置（建议至少设置 2-3 条可评估目标）" : "Not set (recommend at least 2-3 assessable goals).")")
        } else {
            for (index, goal) in goals.enumerated() {
                lines.append("\(index + 1). \(goal)")
            }
        }
        lines.append("")

        lines.append("## \(isChinese ? "3. 学生与支持信息" : "3. Learner Profile & Support")")
        lines.append("| \(isChinese ? "项目" : "Item") | \(isChinese ? "内容" : "Value") |")
        lines.append("|---|---|")
        lines.append("| \(isChinese ? "前测均值" : "Prior Assessment") | \(fallbackPercent(context.studentPriorKnowledgeLevel, isChinese: isChinese)) |")
        lines.append("| \(isChinese ? "作业完成率" : "Assignment Completion") | \(fallbackPercent(context.studentMotivationLevel, isChinese: isChinese)) |")
        lines.append("| \(isChinese ? "支持备注" : "Support Notes") | \(fallback(context.studentSupportNotes, isChinese: isChinese)) |")
        lines.append("| \(isChinese ? "资源约束" : "Resource Constraints") | \(fallback(context.resourceConstraints, isChinese: isChinese)) |")
        lines.append("")

        lines.append("## \(isChinese ? "4. 课堂流程总览" : "4. Lesson Flow Overview")")
        if overviewRows.isEmpty {
            lines.append("- \(isChinese ? "当前画布还没有可编排的知识环节。" : "No teachable knowledge stages found in current canvas.")")
        } else {
            lines.append("| Index | Step | Knowledge | Toolkit | Core Content |")
            lines.append("|---|---|---|---|---|")

            for (index, row) in overviewRows.enumerated() {
                let toolkitCell = row.toolkits.isEmpty ? "-" : row.toolkits.joined(separator: "<br>")
                lines.append(
                    "| \(index + 1) | \(escapeTable(row.stepTitle)) | \(escapeTable(row.knowledge)) | \(escapeTable(toolkitCell)) | \(escapeTable(row.coreContent)) |"
                )
            }
        }
        lines.append("")

        lines.append("## \(isChinese ? "5. 逐步活动说明" : "5. Step-by-step Activity Guide")")
        if mainFlow.isEmpty {
            lines.append("- \(isChinese ? "暂无可展开的课堂环节。" : "No lesson stages available for detailed planning.")")
        } else {
            let mainIDs = Set(mainFlow.map(\.id))
            for (index, node) in mainFlow.enumerated() {
                lines.append("### \(isChinese ? "步骤" : "Step") \(index + 1) · \(node.title)")
                lines.append("- \(isChinese ? "环节定位" : "Stage Positioning"): \(node.kindLabel)")
                if !node.methodOrLevelLabel.isEmpty {
                    lines.append("- \(isChinese ? "教学方式/认知层级" : "Teaching Mode / Cognitive Level"): \(node.methodOrLevelLabel)")
                }

                let inputs = graph.incomingTitles(for: node.id, limitedTo: mainIDs)
                let transitionText = inputs.isEmpty
                    ? (node.isKnowledge
                        ? (isChinese ? "可独立开展，无明显前置限制。" : "Can run independently without strict prerequisite.")
                        : (isChinese ? "建议在前序知识或活动后实施。" : "Recommended after preceding knowledge or activity stage."))
                    : inputs.joined(separator: " / ")
                lines.append("- \(isChinese ? "前置与衔接" : "Prerequisite & Transition"): \(transitionText)")

                let teacherAction = node.isKnowledge
                    ? (isChinese ? "围绕该知识点开展讲授、提问与理解巩固。" : "Deliver explanation, questioning and consolidation around this knowledge point.")
                    : node.formProcessSummary
                lines.append("- \(isChinese ? "教师活动" : "Teacher Action"): \(teacherAction)")
                lines.append("- \(isChinese ? "学生活动与产出" : "Learner Activity & Outcome"): \(node.shortSummary)")

                let filledFields = node.detailedFieldLines
                if !filledFields.isEmpty {
                    lines.append("- \(isChinese ? "实施要点" : "Implementation Notes"):")
                    for field in filledFields {
                        lines.append("  - \(field)")
                    }
                }
                lines.append("")
            }
        }

        lines.append("## \(isChinese ? "6. 评价与证据" : "6. Assessment & Evidence")")
        if evaluation.isEmpty {
            lines.append("- \(isChinese ? "当前未形成完整评价环节，建议补充评价指标与汇总策略。" : "No complete assessment section detected; consider adding metrics and summary strategy.")")
        } else {
            lines.append("| \(isChinese ? "评价环节" : "Assessment Stage") | \(isChinese ? "评价方式" : "Assessment Approach") | \(isChinese ? "证据与说明" : "Evidence & Notes") |")
            lines.append("|---|---|---|")
            for node in evaluation {
                lines.append("| \(escapeTable(node.title)) | \(escapeTable(node.kindLabel)) | \(escapeTable(node.shortSummary)) |")
            }
        }
        lines.append("")

        lines.append("## \(isChinese ? "7. 课后延伸与反思" : "7. Extension & Reflection")")
        let extensionNodes = mainFlow.filter(\.isAfterClassNode)
        if extensionNodes.isEmpty {
            lines.append("- \(isChinese ? "当前未识别到明确课后延伸活动（可在环节名称中加入“课后/After-class”）。" : "No explicit after-class extension activity detected (consider adding \"After-class\" markers in stage titles).")")
        } else {
            for node in extensionNodes {
                lines.append("- \(node.title)：\(node.shortSummary)")
            }
        }
        lines.append("")
        lines.append("- \(isChinese ? "课后反思问题" : "Post-lesson Reflection Prompts")")
        lines.append("  1. \(isChinese ? "哪些课堂环节衔接最顺畅？哪些环节需要补充材料或调整时长？" : "Which stage transitions were smooth, and which stages need more materials or time adjustment?")")
        lines.append("  2. \(isChinese ? "学生在哪个环节出现明显困难？原因是什么？" : "At which stage did learners struggle most, and why?")")
        lines.append("  3. \(isChinese ? "下一次迭代优先优化哪一段课堂流程？" : "Which part of the lesson flow should be prioritized in the next iteration?")")

        return lines.joined(separator: "\n")
    }

    private static var prefersChineseUI: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private static func splitMultilineItems(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "\n" || $0 == ";" || $0 == "；" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func nonEmpty(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func fallback(_ text: String, isChinese: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return isChinese ? "未设置" : "Not set"
    }

    private static func fallbackPercent(_ text: String, isChinese: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return isChinese ? "未设置" : "Not set"
        }
        if trimmed.hasSuffix("%") { return trimmed }
        return "\(trimmed)%"
    }

    private static func escapeTable(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func buildLessonOverviewRows(graph: ParsedGraph, isChinese: Bool) -> [LessonOverviewRow] {
        graph.knowledgeNodes.map { knowledgeNode in
            let toolkitNodes = graph.linkedToolkitNodes(for: knowledgeNode.id)
            let toolkitLabels = toolkitNodes.map { toolkit in
                let mode = toolkit.methodOrLevelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                if mode.isEmpty { return toolkit.title }
                return isChinese ? "\(toolkit.title)（\(mode)）" : "\(toolkit.title) (\(mode))"
            }
            let knowledgeText = knowledgeNode.lessonKnowledgeText
            let coreContent = composeOverviewCoreContent(
                knowledgeText: knowledgeText,
                toolkitLabels: toolkitLabels,
                isChinese: isChinese
            )
            return LessonOverviewRow(
                stepTitle: knowledgeNode.title,
                knowledge: knowledgeText,
                toolkits: toolkitLabels,
                coreContent: coreContent
            )
        }
    }

    private static func composeOverviewCoreContent(
        knowledgeText: String,
        toolkitLabels: [String],
        isChinese: Bool
    ) -> String {
        if toolkitLabels.isEmpty {
            return knowledgeText
        }
        let toolkitPhrase = toolkitLabels.joined(separator: isChinese ? "、" : ", ")
        let sentence = isChinese
            ? "围绕\(knowledgeText)组织学习，并通过\(toolkitPhrase)完成理解巩固与应用迁移。"
            : "Center learning on \(knowledgeText), then reinforce and transfer through \(toolkitPhrase)."
        return sentence
    }

    #if canImport(UIKit)
    private static func renderPDF(markupHTML: String, title: String) -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        let printableRect = pageRect.insetBy(dx: 32, dy: 36)

        let formatter = UIMarkupTextPrintFormatter(markupText: markupHTML)
        formatter.startPage = 0
        formatter.perPageContentInsets = .zero

        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        renderer.setValue(NSValue(cgRect: pageRect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printableRect), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(
            data,
            pageRect,
            [kCGPDFContextTitle as String: title]
        )
        let pageCount = max(renderer.numberOfPages, 1)
        for pageIndex in 0..<pageCount {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: pageIndex, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }
    #else
    private static func renderPDF(markupHTML: String, title: String) -> Data? {
        _ = markupHTML
        _ = title
        return nil
    }
    #endif
}

private struct LessonOverviewRow {
    let stepTitle: String
    let knowledge: String
    let toolkits: [String]
    let coreContent: String
}

private struct ParsedGraph {
    let nodesByID: [UUID: ParsedGraphNode]
    let orderedNodes: [ParsedGraphNode]
    let incomingByNode: [UUID: [UUID]]
    let outgoingByNode: [UUID: [UUID]]
    let isChinese: Bool

    init(document: GNodeDocument, isChinese: Bool) {
        self.isChinese = isChinese

        let stateByID = Dictionary(uniqueKeysWithValues: document.canvasState.map { ($0.nodeID, $0) })
        var parsed: [ParsedGraphNode] = []
        parsed.reserveCapacity(document.nodes.count)

        for serialized in document.nodes {
            let state = stateByID[serialized.id]
            parsed.append(
                ParsedGraphNode(
                    serialized: serialized,
                    state: state,
                    isChinese: isChinese
                )
            )
        }

        self.orderedNodes = parsed.sorted { lhs, rhs in
            if lhs.position.x != rhs.position.x { return lhs.position.x < rhs.position.x }
            if lhs.position.y != rhs.position.y { return lhs.position.y < rhs.position.y }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        self.nodesByID = Dictionary(uniqueKeysWithValues: orderedNodes.map { ($0.id, $0) })

        var incoming: [UUID: [UUID]] = [:]
        var outgoing: [UUID: [UUID]] = [:]
        for connection in document.connections {
            incoming[connection.targetNodeID, default: []].append(connection.sourceNodeID)
            outgoing[connection.sourceNodeID, default: []].append(connection.targetNodeID)
        }
        self.incomingByNode = incoming
        self.outgoingByNode = outgoing
    }

    var mainFlowNodes: [ParsedGraphNode] {
        orderedNodes.filter { $0.isKnowledge || $0.isToolkit }
    }

    var evaluationNodes: [ParsedGraphNode] {
        orderedNodes.filter { $0.isEvaluationLike }
    }

    var knowledgeNodes: [ParsedGraphNode] {
        orderedNodes.filter(\.isKnowledge)
    }

    func incomingTitles(for targetID: UUID, limitedTo allowed: Set<UUID>? = nil) -> [String] {
        let incoming = incomingByNode[targetID] ?? []
        var seen = Set<String>()
        var result: [String] = []
        for sourceID in incoming {
            if let allowed, !allowed.contains(sourceID) { continue }
            guard let node = nodesByID[sourceID] else { continue }
            if seen.insert(node.title).inserted {
                result.append(node.title)
            }
        }
        return result
    }

    func linkedToolkitNodes(for knowledgeID: UUID) -> [ParsedGraphNode] {
        let outgoingIDs = outgoingByNode[knowledgeID] ?? []
        let incomingIDs = incomingByNode[knowledgeID] ?? []
        let relatedIDs = Set(outgoingIDs + incomingIDs)
        guard !relatedIDs.isEmpty else { return [] }
        return orderedNodes.filter { relatedIDs.contains($0.id) && $0.isToolkit }
    }
}

private struct ParsedGraphNode {
    let id: UUID
    let nodeType: String
    let title: String
    let position: CGPoint
    let role: String?
    let textValue: String
    let selectedOption: String
    let selectedMethodID: String?
    let formTextFields: [NodeEditorTextFieldSpec]
    let formOptionFields: [NodeEditorOptionFieldSpec]
    let isChinese: Bool

    init(serialized: SerializableNode, state: CanvasNodeState?, isChinese: Bool) {
        self.id = serialized.id
        self.nodeType = serialized.nodeType
        self.isChinese = isChinese
        self.position = CGPoint(
            x: state?.positionX ?? 0,
            y: state?.positionY ?? 0
        )

        let custom = state?.customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = custom.isEmpty ? serialized.attributes.name : custom
        self.role = ParsedGraphNode.parseRole(serialized.attributes.description)

        var textValue = ""
        var selectedOption = ""
        var selectedMethodID: String?
        var textFields: [NodeEditorTextFieldSpec] = []
        var optionFields: [NodeEditorOptionFieldSpec] = []

        if let liveNode = try? deserializeNode(serialized) {
            if let textEditable = liveNode as? NodeTextEditable {
                textValue = textEditable.editorTextValue
            }
            if let optionSelectable = liveNode as? NodeOptionSelectable {
                selectedOption = optionSelectable.editorSelectedOption
            }
            if let methodSelectable = liveNode as? NodeMethodSelectable {
                selectedMethodID = methodSelectable.editorSelectedMethodID
            }
            if let formEditable = liveNode as? NodeFormEditable {
                textFields = formEditable.editorFormTextFields
                optionFields = formEditable.editorFormOptionFields
            }
        }

        if textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textValue = serialized.nodeData["content"] ?? serialized.nodeData["value"] ?? ""
        }
        if selectedOption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedOption = serialized.nodeData["level"] ?? serialized.nodeData["toolkitType"] ?? ""
        }
        if selectedMethodID == nil {
            selectedMethodID = serialized.nodeData["toolkitMethodID"]
        }

        self.textValue = textValue
        self.selectedOption = selectedOption
        self.selectedMethodID = selectedMethodID
        self.formTextFields = textFields
        self.formOptionFields = optionFields
    }

    var isKnowledge: Bool {
        nodeType == EduNodeType.knowledge
    }

    var isToolkit: Bool {
        EduNodeType.allToolkitTypes.contains(nodeType)
    }

    var isEvaluationLike: Bool {
        nodeType == EduNodeType.evaluation
            || nodeType == EduNodeType.metricValue
            || nodeType == EduNodeType.evaluationMetric
            || nodeType == EduNodeType.evaluationSummary
            || (role?.contains("evaluation") == true)
    }

    var kindLabel: String {
        if isKnowledge {
            return isChinese ? "知识讲授" : "Knowledge Teaching"
        }
        if isToolkit {
            switch nodeType {
            case EduNodeType.toolkitPerceptionInquiry:
                return isChinese ? "活动设计·探究" : "Activity · Inquiry"
            case EduNodeType.toolkitConstructionPrototype:
                return isChinese ? "活动设计·建构" : "Activity · Construction"
            case EduNodeType.toolkitCommunicationNegotiation:
                return isChinese ? "活动设计·协作协商" : "Activity · Negotiation"
            case EduNodeType.toolkitRegulationMetacognition:
                return isChinese ? "活动设计·反思调节" : "Activity · Metacognition"
            default:
                return isChinese ? "活动设计" : "Activity Design"
            }
        }
        if isEvaluationLike {
            return isChinese ? "评价环节" : "Assessment Stage"
        }
        return isChinese ? "辅助环节" : "Supporting Stage"
    }

    var methodOrLevelLabel: String {
        if isKnowledge {
            return selectedOption.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if isToolkit {
            return selectedOption.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    var shortSummary: String {
        if isKnowledge {
            let value = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty
                ? (isChinese ? "（未填写核心内容）" : "(Core content not filled)")
                : Self.compact(value, maxLength: 88)
        }

        if isToolkit {
            let primary = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !primary.isEmpty { return Self.compact(primary, maxLength: 88) }

            if let firstFilled = formTextFields.first(where: {
                !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                let value = Self.compact(firstFilled.value, maxLength: 70)
                return "\(firstFilled.label): \(value)"
            }
            return isChinese ? "（未填写活动说明）" : "(Activity details not filled)"
        }

        if isEvaluationLike {
            let primary = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !primary.isEmpty { return Self.compact(primary, maxLength: 88) }

            if let firstFilledOption = formOptionFields.first(where: {
                !$0.selectedOption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                return "\(firstFilledOption.label): \(Self.compact(firstFilledOption.selectedOption, maxLength: 60))"
            }
            if let firstFilledField = formTextFields.first(where: {
                !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                let value = Self.compact(firstFilledField.value, maxLength: 70)
                return "\(firstFilledField.label): \(value)"
            }
            return isChinese ? "（未填写评价说明）" : "(Evaluation details not filled)"
        }

        let value = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? (isChinese ? "（无说明）" : "(No description)") : Self.compact(value, maxLength: 88)
    }

    var lessonKnowledgeText: String {
        let value = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return isChinese ? "（未填写知识点）" : "(Knowledge point not filled)"
        }
        return Self.compact(value, maxLength: 180)
    }

    var formProcessSummary: String {
        if !methodOrLevelLabel.isEmpty {
            return isChinese
                ? "围绕“\(methodOrLevelLabel)”组织活动并落实字段要求。"
                : "Run this stage around \"\(methodOrLevelLabel)\" with configured field requirements."
        }
        return isChinese ? "按当前设置组织教学活动。" : "Run this stage based on current configuration."
    }

    var detailedFieldLines: [String] {
        var lines: [String] = []

        for field in formOptionFields {
            let selected = field.selectedOption.trimmingCharacters(in: .whitespacesAndNewlines)
            if selected.isEmpty {
                if !field.isOptional {
                    lines.append("\(field.label): \(isChinese ? "[必填未填]" : "[Required, missing]")")
                }
            } else {
                lines.append("\(field.label): \(Self.compact(selected, maxLength: 120))\(optionalSuffix(field.isOptional))")
            }
        }

        for field in formTextFields {
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                if !field.isOptional {
                    lines.append("\(field.label): \(isChinese ? "[必填未填]" : "[Required, missing]")")
                }
            } else {
                lines.append("\(field.label): \(Self.compact(value, maxLength: 140))\(optionalSuffix(field.isOptional))")
            }
        }

        return lines
    }

    var isAfterClassNode: Bool {
        let lower = title.lowercased()
        if lower.contains("after-class") || lower.contains("after class") || lower.contains("post-class") {
            return true
        }
        if title.contains("课后") || title.contains("月度") || title.contains("延伸") {
            return true
        }
        return false
    }

    private func optionalSuffix(_ optional: Bool) -> String {
        optional ? (isChinese ? "（可选）" : " (Optional)") : ""
    }

    private static func compact(_ text: String, maxLength: Int) -> String {
        let flattened = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        if flattened.count <= maxLength { return flattened }
        return String(flattened.prefix(maxLength)) + "..."
    }

    private static func parseRole(_ description: String) -> String? {
        let prefix = "edunode.role="
        guard let range = description.range(of: prefix) else { return nil }
        let raw = description[range.upperBound...]
        let role = raw.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let role, !role.isEmpty else { return nil }
        return role
    }
}
