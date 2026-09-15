import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  readonly property real u: iconSize / 32

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    antialiasing: true
    layer.enabled: true
    layer.samples: 4
    layer.smooth: true
    layer.textureSize: Qt.size(
      Math.max(1, Math.round(width * Screen.devicePixelRatio)),
      Math.max(1, Math.round(height * Screen.devicePixelRatio))
    )

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: 1.6 * root.u
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      PathRectangle {
        x: 2.5 * root.u
        y: 2.5 * root.u
        width: 27 * root.u
        height: 27 * root.u
        radius: 6.5 * root.u
      }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: 1.85 * root.u
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: 11.5 * root.u
      startY: 10.75 * root.u

      PathLine { x: 7.25 * root.u; y: 16 * root.u }
      PathLine { x: 11.5 * root.u; y: 21.25 * root.u }
    }

    ShapePath {
      fillColor: root.color
      strokeWidth: 0

      PathRectangle {
        x: 14.5 * root.u
        y: 13.85 * root.u
        width: 4.3 * root.u
        height: 4.3 * root.u
        radius: 1 * root.u
      }
    }

    ShapePath {
      fillColor: Qt.alpha(root.color, 0.58)
      strokeWidth: 0

      PathRectangle {
        x: 20 * root.u
        y: 14.2 * root.u
        width: 3.6 * root.u
        height: 3.6 * root.u
        radius: 0.9 * root.u
      }
    }

    ShapePath {
      fillColor: Qt.alpha(root.color, 0.28)
      strokeWidth: 0

      PathRectangle {
        x: 24.6 * root.u
        y: 14.55 * root.u
        width: 2.9 * root.u
        height: 2.9 * root.u
        radius: 0.8 * root.u
      }
    }
  }
}
