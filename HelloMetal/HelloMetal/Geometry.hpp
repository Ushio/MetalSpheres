#include <vector>
#include <simd/simd.h>

namespace Geometry {
    typedef uint16_t IndexType;
    
    struct IcoSphereVertex {
        simd::float3 position;
        simd::float3 normal;
    };
    struct IcoSphereModel {
        std::vector<IcoSphereVertex> vertices;
        std::vector<IndexType> indices;
        
        IcoSphereModel() = default;
        IcoSphereModel(IcoSphereModel&&) = default;
        IcoSphereModel& operator=(const IcoSphereModel& rhs) = default;
    };
    
    IcoSphereModel createIcosphere(int subdivideCount);
}