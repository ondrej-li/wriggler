import Foundation
import Testing
import WrigglerCore

@Suite("Items")
struct ItemTests {
    private func worldWithItems(_ items: [(ItemKind, Vec2)]) throws -> MazeWorld {
        let base = try TestMaze.corridor()
        return MazeWorld(
            maze: base,
            items: [
                RoomID("0,0")!: items.enumerated().map { index, entry in
                    Item(id: index, kind: entry.0, position: entry.1)
                }
            ])
    }

    @Test("Picks up an object when empty handed")
    func pickup() throws {
        var world = try worldWithItems([(.key, Vec2(x: 2.3, y: 3))])
        #expect(world.player.carried == nil)

        let event = world.interact()

        #expect(event == .pickedUp(.key))
        #expect(world.player.carried?.kind == .key)
        #expect(world.itemsInRoom.isEmpty)
    }

    @Test("Swaps when already carrying something")
    func swap() throws {
        var world = try worldWithItems([
            (.key, Vec2(x: 2.2, y: 3)),
            (.mug, Vec2(x: 2.9, y: 3)),
        ])

        #expect(world.interact() == .pickedUp(.key))
        let event = world.interact()

        #expect(event == .swapped(dropped: .key, picked: .mug))
        #expect(world.player.carried?.kind == .mug)
        #expect(world.itemsInRoom.map(\.kind) == [.key], "the key should be left behind")
    }

    @Test("The dropped object stays where the new one was")
    func swapKeepsPosition() throws {
        var world = try worldWithItems([
            (.key, Vec2(x: 2.2, y: 3)),
            (.bottle, Vec2(x: 2.9, y: 3.4)),
        ])
        _ = world.interact()  // take the key
        _ = world.interact()  // swap for the bottle

        let dropped = try #require(world.itemsInRoom.first)
        #expect(dropped.kind == .key)
        #expect(dropped.position == Vec2(x: 2.9, y: 3.4))
    }

    @Test("Out of reach objects are not picked up")
    func outOfReach() throws {
        var world = try worldWithItems([(.skull, Vec2(x: 8, y: 3))])
        #expect(world.interact() == .nothingToDo)
        #expect(world.player.carried == nil)
        #expect(world.itemsInRoom.count == 1)
    }

    @Test("Pressing the button with something in hand and nothing underfoot uses it")
    func useWhenEmptyHandedTarget() throws {
        var world = try worldWithItems([(.tombstone, Vec2(x: 2.2, y: 3))])
        _ = world.interact()
        #expect(world.player.carried?.kind == .tombstone)

        // Walk away from where it was, then press again.
        _ = world.run(frames: 40, input: GameInput(moveX: 1))
        #expect(world.interact() == .used(.tombstone))
        #expect(world.player.carried?.kind == .tombstone, "using does not consume the object yet")
    }

    @Test("Restart puts the items back")
    func restart() throws {
        var world = try worldWithItems([(.key, Vec2(x: 2.2, y: 3))])
        _ = world.interact()
        #expect(world.itemsInRoom.isEmpty)

        world.restart()

        #expect(world.player.carried == nil)
        #expect(world.itemsInRoom.count == 1)
        #expect(world.roomID == RoomID("0,0"))
    }
}
