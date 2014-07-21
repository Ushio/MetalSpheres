#include "Geometry.hpp"
#include <tuple>
#include <algorithm>
#include <array>
#include <cmath>

namespace {
    typedef std::tuple<Geometry::IndexType, Geometry::IndexType, Geometry::IndexType> FaceType;
    std::tuple<std::vector<simd::float3>, std::vector<FaceType>> subdivide(std::vector<simd::float3> vertices,
                                                                                                        std::vector<FaceType> faces,
                                                                                                        int n)
    {
        if(n == 0)
        {
            return std::make_tuple(std::move(vertices), std::move(faces));
        }
        
        std::vector<FaceType> faces_out;
        
        for(auto f : faces)
        {
            auto a = vector_mix(vertices[std::get<0>(f)], vertices[std::get<1>(f)], 0.5f);
            auto b = vector_mix(vertices[std::get<1>(f)], vertices[std::get<2>(f)], 0.5f);
            auto c = vector_mix(vertices[std::get<2>(f)], vertices[std::get<0>(f)], 0.5f);
            
            vertices.push_back(a);
            vertices.push_back(b);
            vertices.push_back(c);
            
            Geometry::IndexType ia = vertices.size() - 3;
            Geometry::IndexType ib = vertices.size() - 2;
            Geometry::IndexType ic = vertices.size() - 1;
            
            faces_out.emplace_back(std::get<0>(f), ia, ic);
            faces_out.emplace_back(std::get<1>(f), ib, ia);
            faces_out.emplace_back(std::get<2>(f), ic, ib);
            faces_out.emplace_back(ia, ib, ic);
        }
        
        return subdivide(std::move(vertices), std::move(faces_out), n - 1);
    }
}
namespace Geometry {
    IcoSphereModel createIcosphere(int subdivideCount) {
        float t = (1.0f + sqrtf(5.0f)) / 2.0f;
        
        std::vector<simd::float3> vertices;
        std::vector<FaceType> faces;
        
        vertices.emplace_back(simd::float3{-1.0f, t, 0.0f});
        vertices.emplace_back(simd::float3{ 1.0f, t, 0.0f});
        vertices.emplace_back(simd::float3{-1.0f,-t, 0.0f});
        vertices.emplace_back(simd::float3{ 1.0f,-t, 0.0f});
        vertices.emplace_back(simd::float3{ 0.0f,-1.0f, t});
        vertices.emplace_back(simd::float3{ 0.0f, 1.0f, t});
        vertices.emplace_back(simd::float3{ 0.0f,-1.0f,-t});
        vertices.emplace_back(simd::float3{ 0.0f, 1.0f,-t});
        vertices.emplace_back(simd::float3{ t, 0.0f,-1.0f});
        vertices.emplace_back(simd::float3{ t, 0.0f, 1.0f});
        vertices.emplace_back(simd::float3{-t, 0.0f,-1.0f});
        vertices.emplace_back(simd::float3{-t, 0.0f, 1.0f});
        
        faces.emplace_back(0, 5, 11);
        faces.emplace_back(0, 1, 5);
        faces.emplace_back(0, 7, 1);
        faces.emplace_back(0, 10, 7);
        faces.emplace_back(0, 11, 10);
        faces.emplace_back(1, 9, 5);
        faces.emplace_back(5, 4, 11);
        faces.emplace_back(11, 2, 10);
        faces.emplace_back(10, 6, 7);
        faces.emplace_back(7, 8, 1);
        faces.emplace_back(3, 4, 9);
        faces.emplace_back(3, 2, 4);
        faces.emplace_back(3, 6, 2);
        faces.emplace_back(3, 8, 6);
        faces.emplace_back(3, 9, 8);
        faces.emplace_back(4, 5, 9);
        faces.emplace_back(2, 11, 4);
        faces.emplace_back(6, 10, 2);
        faces.emplace_back(8, 7, 6);
        faces.emplace_back(9, 1, 8);
        
        std::tie(vertices, faces) = subdivide(std::move(vertices), std::move(faces), subdivideCount);
        
        IcoSphereModel model;
        for(auto p : vertices)
        {
            IcoSphereVertex v;
            v.position = simd::normalize(p);
            v.normal = v.position;
            model.vertices.push_back(v);
        }
        
        for(auto f : faces)
        {
            std::array<IndexType, 3> index;
            std::tie(index[0], index[1], index[2]) = f;
            for(auto i : index)
            {
                model.indices.push_back(i);
            }
        }
        
        return model;
    }

}
