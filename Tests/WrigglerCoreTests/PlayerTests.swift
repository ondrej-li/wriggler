import Testing
import WrigglerCore

@Suite("Player")
struct PlayerTests {
    private func flatLevel(spawnX: Int = 1) -> Level {
        TestMap.level(
            [
                "..........",
                "..........",
                "..........",
                "##########",
            ], spawn: GridPoint(x: spawnX, y: 2))
    }

    @Test("Spawn places the feet on the bottom of the spawn cell")
    func spawnPosition() {
        let player = Player(spawnCell: GridPoint(x: 2, y: 4))
        #expect(player.body.feet == 5)
        #expect(abs(player.body.center.x - 2.5) < 0.001)
    }

    @Test("Standing still settles on the ground")
    func settlesOnGround() {
        var world = World(level: flatLevel())
        world.run(seconds: 0.2)

        #expect(world.player.body.isOnGround)
        #expect(world.player.body.feet == 3)
        #expect(world.player.state == .idle)
    }

    @Test("Jumping launches the player upwards")
    func jump() {
        var world = World(level: flatLevel())
        world.run(seconds: 0.2)
        world.run(seconds: 1.0 / 60.0, input: GameInput(jumpPressed: true, jumpHeld: true))

        #expect(world.player.body.velocity.y < 0)
        #expect(!world.player.body.isOnGround)
        #expect(world.player.state == .jumping)
    }

    @Test("Releasing jump early cuts the arc short")
    func jumpCut() {
        var world = World(level: flatLevel())
        world.run(seconds: 0.2)
        world.run(seconds: 1.0 / 120.0, input: GameInput(jumpPressed: true, jumpHeld: true))
        let launchSpeed = world.player.body.velocity.y
        world.run(seconds: 1.0 / 120.0, input: GameInput(jumpHeld: false))
        let cutSpeed = world.player.body.velocity.y

        #expect(launchSpeed < -15)
        #expect(cutSpeed > launchSpeed)
        #expect(cutSpeed > -10)
    }

    @Test("Coyote time allows a jump just after walking off a ledge")
    func coyoteTime() {
        var world = World(
            level: TestMap.level(
                [
                    ".........",
                    ".........",
                    ".........",
                    ".........",
                    "###......",
                ], spawn: GridPoint(x: 1, y: 3)))
        world.run(seconds: 0.2)

        var frames = 0
        while world.player.body.isOnGround, frames < 120 {
            world.run(seconds: 1.0 / 60.0, input: GameInput(moveX: 1))
            frames += 1
        }
        #expect(!world.player.body.isOnGround, "player should have walked off the ledge")

        world.run(seconds: 1.0 / 120.0, input: GameInput(moveX: 1, jumpPressed: true, jumpHeld: true))
        #expect(world.player.body.velocity.y < 0, "coyote jump should still fire")
    }

    @Test("Climbing a ladder disables gravity")
    func climbing() {
        var world = World(
            level: TestMap.level(
                [
                    "..H..",
                    "..H..",
                    "..H..",
                    "#####",
                ], spawn: GridPoint(x: 2, y: 2)))
        world.run(seconds: 0.2)

        let startY = world.player.body.position.y
        world.run(seconds: 0.2, input: GameInput(moveY: -1))

        #expect(world.player.body.isClimbing)
        #expect(world.player.state == .climbing)
        #expect(world.player.body.position.y < startY)
    }

    @Test("Facing follows input")
    func facing() {
        var world = World(level: flatLevel())
        world.run(seconds: 0.2)

        world.run(seconds: 0.1, input: GameInput(moveX: -1))
        #expect(world.player.facing == .left)

        world.run(seconds: 0.1, input: GameInput(moveX: 1))
        #expect(world.player.facing == .right)
    }
}
