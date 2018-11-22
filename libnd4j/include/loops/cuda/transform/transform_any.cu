/*******************************************************************************
 * Copyright (c) 2015-2018 Skymind, Inc.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Apache License, Version 2.0 which is available at
 * https://www.apache.org/licenses/LICENSE-2.0.
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations
 * under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 ******************************************************************************/

//
// @author raver119@gmail.com
//

#include <Environment.h>
#include <loops/transform_any.h>
#include <types/types.h>
#include <op_boilerplate.h>

#include <loops/legacy_ops.h>
#include <helpers/DebugHelper.h>

using namespace simdOps;


template<typename X, typename Z, typename OpClass>
__device__ void transformAnySimpleGeneric(
		Nd4jLong n,
		void *dy,
		Nd4jLong incy,
		void *params,
		void *result,
		Nd4jLong resultStride, int *allocationPointer, void *reductionPointer) {

	functions::transform::TransformAny<X,Z>::template transformCuda<OpClass>(
		n,
		dy,
		incy,
		params,
		result,
		resultStride,
		allocationPointer,
		reductionPointer,
		nullptr);
}

template<typename X, typename Z, typename OpClass>
__device__ void transformAnySimpleGeneric(
		void *dy,
		Nd4jLong *xShapeInfo, int xRank,
		void *params,
		void *result, Nd4jLong *zShapeInfo, int zRank, int *allocationPointer, void *reductionPointer, Nd4jLong *tadShapeInfo, Nd4jLong *tadOffsets) {

	__shared__ UnifiedSharedMemory *manager;

	if (threadIdx.x == 0) {
		extern __shared__ unsigned char shmem[];
		manager = new(shmem) UnifiedSharedMemory((int *) shmem);
		manager->init(sizeof(UnifiedSharedMemory), 0, sizeof(functions::transform::TransformAny<X,Z>), sizeof(shape::TAD), xRank);
	}
	__syncthreads();
	
    functions::transform::TransformAny<X,Z>::template transformCuda<OpClass>(
	    dy,
	    xShapeInfo,
	    params,
	    result,
	    zShapeInfo,
	    allocationPointer,
	    reductionPointer,
		manager, tadShapeInfo, tadOffsets);
}


template <typename X, typename Z, typename OpType>
__global__ void transformAnySimple(void *dy, Nd4jLong *xShapeInfo, int xRank,
								void *params,
								void *result, Nd4jLong *zShapeInfo, int zRank,
								int *allocationPointer,
								void *reductionPointer,
								Nd4jLong *tadShapeInfo, Nd4jLong *tadOffsets) {
	transformAnySimpleGeneric<X, Z, OpType>(dy, xShapeInfo, xRank, params, result, zShapeInfo, zRank, allocationPointer, reductionPointer, tadShapeInfo, tadOffsets);
}


namespace functions {
    namespace transform {

        template<typename X, typename Y>
        _CUDA_H void TransformAny<X,Y>::executeTransformShaped(dim3 launchDims, cudaStream_t *stream, int opNum, void *x, Nd4jLong *xShape, int xRank, void *extraParams, void *z, Nd4jLong *zShape, int zRank, int *allocationPointer, void *reductionPointer,  Nd4jLong *tadShapeInfo, Nd4jLong *tadOffsets) {
			DISPATCH_BY_OPNUM_TT(intermediateShaped, PARAMS(launchDims, stream, x, xShape, xRank, extraParams, z, zShape, zRank, allocationPointer, reductionPointer, tadShapeInfo, tadOffsets), TRANSFORM_ANY_OPS);

            DEBUG_KERNEL(stream, opNum);
        }


        template<typename X, typename Z>
        template <typename OpType>
        __device__ void TransformAny<X,Z>::transformCuda(
			void *vdy,
			Nd4jLong *shapeInfo,
			void *vparams,
			void *vresult,
			Nd4jLong *zShapeInfo,
			int *allocationPointer, void *vreductionPointer, UnifiedSharedMemory *manager, Nd4jLong *tadShapeInfo, Nd4jLong *tadOffsets) {

        	auto dy = static_cast<X*>(vdy);
		    auto result = static_cast<Z*>(vresult);
		    auto params = static_cast<X*>(vparams);
		    auto reductionPointer = static_cast<Z*>(vreductionPointer);

		    auto xOrder = shape::order(shapeInfo);
		    auto zOrder = shape::order(zShapeInfo);

		    auto xEws = shape::elementWiseStride(shapeInfo);
		    auto zEws = shape::elementWiseStride(zShapeInfo);
		    auto tid = blockIdx.x * blockDim.x + threadIdx.x;

		    __shared__ Nd4jLong length;
		    if(threadIdx.x == 0)
		        length = shape::length(shapeInfo);
		    __syncthreads();

		    if(xEws >= 1 && zEws >= 1 && xOrder == zOrder) {
		        transformCuda<OpType>(
				    	length,
				    	dy,
				    	xEws,
				    	params,
				    	result,
				    	zEws, allocationPointer, reductionPointer, manager);
		    } else {
		        for (Nd4jLong i = tid; i < length; i+= gridDim.x * blockDim.x) {
		            auto xOffset2 = shape::getIndexOffset(i, shapeInfo,  length);
		            auto zOffset2 = shape::getIndexOffset(i, zShapeInfo, length);
		            result[zOffset2] = OpType::op(dy[xOffset2], params);
		        }
		    }
	    };

        template<typename X, typename Z>
        template <typename OpType>
	    __device__ void TransformAny<X,Z>::transformCuda(
			Nd4jLong n,
			void *vdy,
			Nd4jLong incy,
			void *vparams,
			void *vresult,
			Nd4jLong resultStride,
			int *allocationPointer, void *vreductionPointer, UnifiedSharedMemory *manager) {
		
        	auto dy = static_cast<X*>(vdy);
		    auto result = static_cast<Z*>(vresult);
		    auto params = static_cast<X*>(vparams);
		    auto reductionPointer = static_cast<Z*>(vreductionPointer);

            int totalThreads = gridDim.x * blockDim.x;
		    Nd4jLong i = blockIdx.x * blockDim.x + threadIdx.x;

    		if(incy == 1 && resultStride == 1) {
	    		/* equal, positive, non-unit increments. */
			    for (; i < n; i += totalThreads) {
				    result[i] = OpType::op(dy[i], params);
			    }
		    }
		    else {
			    for (; i < n; i += totalThreads) {
				    result[i * resultStride] = OpType::op(dy[i * incy], params);
			    }
		    }
	    }


		template<typename X, typename Z>
		template <typename OpType>
		_CUDA_H void TransformAny<X,Z>::intermediateShaped(dim3 launchDims, cudaStream_t *stream, void *x, Nd4jLong *xShape, int xRank, void *extraParams, void *z, Nd4jLong *zShape, int zRank, int *allocationPointer, void *reductionPointer,  Nd4jLong *tadShapeInfo, Nd4jLong *tadOffsets) {
			transformAnySimple<X, Z, OpType><<<launchDims.x, launchDims.y, launchDims.z, *stream>>>(x, xShape, xRank, extraParams, z, zShape, zRank, allocationPointer, reductionPointer, tadShapeInfo, tadOffsets);
		}

        BUILD_DOUBLE_TEMPLATE(template class ND4J_EXPORT TransformAny, , LIBND4J_TYPES, LIBND4J_TYPES);
    }
}
