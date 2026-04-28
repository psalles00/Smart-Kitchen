import SwiftUI

/// Shape decorativo que traça uma linha ondulada inset, seguindo a forma do
/// painel branco da página (`UnevenRoundedRectangle` com cantos superiores
/// arredondados). Usado como overlay no dashboard de Nutrição para indicar
/// dias com registro iniciado e não concluído (amarelo) e dias concluídos
/// (verde) — sem deslocar nenhum componente existente.
struct WavyPanelBorder: Shape {
    /// Raio dos cantos superiores do painel host (ExpandedPageLayout = 24).
    var cornerRadius: CGFloat = 24
    /// Distância da linha em relação às bordas do painel.
    var inset: CGFloat = 6
    /// Amplitude do seno (afastamento perpendicular máximo da linha base).
    var amplitude: CGFloat = 1.6
    /// Comprimento de onda do seno em pontos.
    var wavelength: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard r.width > 0, r.height > 0 else { return Path() }

        let cr = max(min(cornerRadius - inset, min(r.width, r.height) / 2), 0)
        let stepLen: CGFloat = 1.5

        // Pontos amostrados ao longo do perímetro (no sentido horário a partir
        // do início do arco superior esquerdo). Acompanhamos também o
        // comprimento de arco acumulado para que o seno fique contínuo entre
        // segmentos.
        var samples: [(point: CGPoint, arc: CGFloat)] = []
        var arcSoFar: CGFloat = 0

        func addLine(from a: CGPoint, to b: CGPoint) {
            let dx = b.x - a.x, dy = b.y - a.y
            let len = (dx * dx + dy * dy).squareRoot()
            guard len > 0 else { return }
            let count = max(Int((len / stepLen).rounded()), 1)
            for i in 0...count {
                let t = CGFloat(i) / CGFloat(count)
                let p = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
                samples.append((p, arcSoFar + len * t))
            }
            arcSoFar += len
        }

        func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) {
            guard radius > 0 else { return }
            let arcLen = abs(endAngle - startAngle) * radius
            let count = max(Int((arcLen / stepLen).rounded()), 4)
            for i in 0...count {
                let t = CGFloat(i) / CGFloat(count)
                let a = startAngle + (endAngle - startAngle) * t
                let p = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
                samples.append((p, arcSoFar + arcLen * t))
            }
            arcSoFar += arcLen
        }

        let topLeftCenter = CGPoint(x: r.minX + cr, y: r.minY + cr)
        let topRightCenter = CGPoint(x: r.maxX - cr, y: r.minY + cr)

        // Sentido horário, começando no início do arco superior esquerdo.
        // (No sistema do iOS, y cresce para baixo.)
        addArc(center: topLeftCenter, radius: cr, startAngle: .pi, endAngle: 1.5 * .pi)
        addLine(from: CGPoint(x: r.minX + cr, y: r.minY), to: CGPoint(x: r.maxX - cr, y: r.minY))
        addArc(center: topRightCenter, radius: cr, startAngle: 1.5 * .pi, endAngle: 2 * .pi)
        addLine(from: CGPoint(x: r.maxX, y: r.minY + cr), to: CGPoint(x: r.maxX, y: r.maxY))
        addLine(from: CGPoint(x: r.maxX, y: r.maxY), to: CGPoint(x: r.minX, y: r.maxY))
        addLine(from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.minX, y: r.minY + cr))

        // Constrói path final aplicando offset perpendicular (seno) ao longo
        // do perímetro. Tangente é estimada por diferenças finitas centrais.
        var path = Path()
        let n = samples.count
        guard n > 2 else { return path }

        for i in 0..<n {
            let prev = samples[(i - 1 + n) % n].point
            let next = samples[(i + 1) % n].point
            let tx = next.x - prev.x
            let ty = next.y - prev.y
            let tlen = (tx * tx + ty * ty).squareRoot()
            guard tlen > 0 else { continue }
            // Normal apontando para "fora" no sentido horário: rotação -90°
            // de (tx, ty) em coordenadas iOS = (ty, -tx). Como queremos que a
            // linha fique para DENTRO da área (não estoure as bordas), invertemos
            // também: usamos amplitude com sinal alternado pela função seno.
            let nx = ty / tlen
            let ny = -tx / tlen

            let phase = samples[i].arc / wavelength * 2 * .pi
            let off = sin(phase) * amplitude
            let p = CGPoint(x: samples[i].point.x + nx * off,
                            y: samples[i].point.y + ny * off)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}
