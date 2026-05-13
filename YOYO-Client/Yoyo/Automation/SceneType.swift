import AVFoundation

enum SceneType: String, CaseIterable, Codable {
    /// General scene
    case general // general/default

    // people-related (YOLO: person)
    case portrait // portrait (single person/close-up)
    case group // group photo (multiple people)

    // animals (YOLO: cat, dog, bird, horse, sheep, cow, elephant, bear, zebra, giraffe)
    case pet // pet (cats and dogs)
    case wildlife // animals/birds

    /// Plant (YOLO: potted plant)
    case plant // plants/flowers

    /// Food (YOLO: banana, apple, sandwich, orange, broccoli, carrot, hot dog, pizza, donut, cake...)
    case food // food

    /// Sports (YOLO: frisbee, skis, snowboard, sports ball, kite, baseball bat, skateboard, surfboard, tennis racket)
    case sports // sports

    // transportation and city (YOLO: car, bus, train, truck, boat, traffic light, stop sign...)
    case vehicle // vehicles
    case cityscape // cityscape/city

    /// Indoor and lifestyle (YOLO: chair, couch, bed, dining table, microwave, sink, clock...)
    case interior // indoor/home

    /// Objects (YOLO: bag, book, bottle, cup, umbrella...)
    case stillLife // still life/objects

    /// Technology (YOLO: laptop, phone, tv, mouse, keyboard)
    case technology // digital/technology
}
