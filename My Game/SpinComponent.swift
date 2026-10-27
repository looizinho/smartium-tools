//
//  SpinComponent.swift
//  My Game
//
//  Created by Luiz Neto on 27/10/26.
//

import RealityKit

/// A component that spins the entity around a given axis.
struct SpinComponent: Component {
    let spinAxis: SIMD3<Float> = [0, 1, 0]
}
