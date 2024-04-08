
import Foundation
import SwiftUI
import OSLog
import GRPC
import SwiftProtobuf


extension CreatureServerClient {
    
    func createAnimation(animation: Animation) async -> Result<String, ServerError> {
        
        guard !animation.id.isEmpty && animation.id.count == 12 else {
            logger.warning("No ID on an animation that was attempted to be created")
            return .failure(.dataFormatError("Animation does not have a valid ID"))
        }
        
        
        logger.info("Attempting to create a new Animation in the database")
        
        logger.debug("Animation Title: \(animation.metadata.title)")
        logger.debug("Number of frames: \(animation.metadata.numberOfFrames)")
                
        do {
            let serverAnimation = animation.toServerAnimation()
            
            guard let response = try await server?.createAnimation(serverAnimation) else {
                logger.error("Server did not return a messate on createAnimation()?")
                return .failure(.unknownError("The server didn't return a response when creating an animation"))
            }
            
            logger.debug("Created a new animation in the database!")
            return .success("Server said: \(response.message)")
            
        }
        catch SwiftProtobuf.BinaryDecodingError.truncated {
            logger.error("Animation was unable to be decoded because it was truncated")
            return .failure(.communicationError("Unable to save animation due to the protobuf being truncated. 😅"))
        }
        catch SwiftProtobuf.BinaryDecodingError.malformedProtobuf {
            logger.error("Animation was unable to be decoded because the protobuf was malformed")
            return .failure(.dataFormatError("Unable to save animation due to the protobuf being malformed. 🤔"))
        }
        catch {
            logger.error("Unable to save an animation to the database: \(error)")
            return .failure(.databaseError("Server said: \(error.localizedDescription), (\(error))"))
        }
    }
    
    /**
     Update an animation in the database.
     
     This effectively called `replace_one()` on the MongoDB side, with the `_id` of the animation we're updating.
     */
    func updateAnimation(animationToUpdate: Animation) async -> Result<String, ServerError> {
        
        guard !animationToUpdate.id.isEmpty && animationToUpdate.id.count == 12 else {
            logger.warning("No ID on an animation that was attempted to be updated")
            return .failure(.dataFormatError("Animation does not have a valid ID, not attempting update"))
        }
        
        
        logger.info("Attempting to update an animation in the database")
 
        do {
            let serverAnimation = animationToUpdate.toServerAnimation()
            
            guard let response = try await server?.updateAnimation(serverAnimation) else {
                logger.error("Server did not return a messate on updateAnimation()?")
                return .failure(.unknownError("The server didn't return a response when updating an animation"))
            }
            
            logger.debug("Animation updated in the database")
            return .success(response.message)
        }
        catch SwiftProtobuf.BinaryDecodingError.truncated {
            logger.error("Animation was unable to be decoded because it was truncated")
            return .failure(.dataFormatError("Unable to update an animation due to the protobuf being truncated. 😅"))
        }
        catch SwiftProtobuf.BinaryDecodingError.malformedProtobuf {
            logger.error("Animation was unable to be decoded because the protobuf was malformed")
            return .failure(.dataFormatError("Unable to update an animation due to the protobuf being malformed. 🤔"))
        }
        catch {
            logger.error("Unable to update an animation in the database: \(error)")
            return .failure(.databaseError("Server said: \(error.localizedDescription), (\(error))"))
        }
    }
    
    
    /**
     Get a list of all of the animations that a creature can play.
     
     This will return an array of AnimationMetadata objects
     */
    func listAnimations(creature: Creature) async -> Result<[AnimationMetadata], ServerError> {
        
        guard !creature.id.isEmpty && creature.id.count == 12 else {
            logger.warning("Unable to get the animations that a creature with a malformed ID can play")
            return .failure(.dataFormatError("Unable to get the animations that a creature with a malformed ID can play"))
        }
        
        // Make this easier on myself
        let idString = DataHelper.dataToHexString(data: creature.id)
    
        logger.info("attempting to get all of the animations that \(creature.name) (id \(idString)) can play")

        
        // Keep the array of animations
        var metadatas: [AnimationMetadata] = []
        
        do {
            var filter = Server_AnimationFilter()
            filter.creatureID = creature.getIdAsServerCreatureId()
            
            
            guard let response = try await server?.listAnimations(filter) else {
                logger.error("Server was unable to get the animations for creature ID \(idString)")
                return .failure(.unknownError("Server was unable to get the animations for creature ID \(idString)"))
            }
            logger.debug("got back animation metdatas from the server!")
            
            // Put these into the container
            for a in response.animations {
                metadatas.append(AnimationMetadata(fromServerAnimationMetadata: a))
            }
            
            logger.info("got all animations for \(creature.name). \(metadatas.count) total")
            return .success(metadatas)
            
        }
        catch {
            logger.error("Unable to get animations for creature \(idString): \(error)")
            return .failure(.otherError("Unable to get animations! Server said: \(error.localizedDescription), (\(error))"))
        }
        
    }
    
    
    /**
     Load an animation from the database by ID
     */
    func getAnimation(animationId: Data) async -> Result<Animation, ServerError>  {
        
        guard !animationId.isEmpty && animationId.count == 12 else {
            logger.warning("Unable to load an animation with a malformed ID")
            return .failure(.dataFormatError("Unable to load an animation with a malformed Id"))
        }
        
        let idString = DataHelper.dataToHexString(data: animationId)
        
        logger.debug("attempting to fetch animation \(idString)")
    
        var id = Server_AnimationId()
        id.id = animationId
        
        do {
            
            
            guard let serverAnimation = try await server?.getAnimation(id) else {
                logger.error("Server was unable to load animation ID \(idString)")
                return .failure(.unknownError("Server was unable to load animation \(idString)"))
            }
            
            logger.debug("got the animation back from the server!")
            return .success(Animation(fromServerAnimation: serverAnimation))
   
    
        }
        catch {
            logger.error("Unable to get animation \(DataHelper.dataToHexString(data: animationId))")
            return .failure(.otherError("Server said: \(error.localizedDescription), (\(error))"))
        }
        
    }
    
    
    
}
